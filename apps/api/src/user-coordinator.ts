import { DurableObject } from "cloudflare:workers";
import type { ChatActivity } from "./chats/chat-types";
import {
  apnsSender,
  type PushAlert,
  type PushEnvironment,
  type PushSender,
} from "./notifications/apns";
import {
  type Notification,
  type NotificationEvent,
  pushTextFor,
} from "./notifications/notification";

type PushText = Pick<PushAlert, "title" | "body" | "group">;

const inboxPageSize = 50;
const inboxRetained = 200;
const devicesRetained = 10;
const reservedCloseCodes = new Set([1005, 1006, 1015]);

interface NotificationRow extends Record<string, SqlStorageValue> {
  id: string;
  event: string;
  created_at: number;
}

interface DeviceRow extends Record<string, SqlStorageValue> {
  token: string;
  environment: PushEnvironment;
}

/**
 * One per person. Keeps their notification inbox, pushes new notifications to
 * their open sockets, and sends connection events to their phones through
 * APNs. The inbox is the record; a socket or a push only announces it.
 */
export class UserCoordinator extends DurableObject<Env> {
  /** Null while the APNs secrets are not set. Tests replace it. */
  pushSender: PushSender | null;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.pushSender = apnsSender(env);
    ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS notification (
        id TEXT PRIMARY KEY,
        event TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS push_device (
        token TEXT PRIMARY KEY,
        environment TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS inbox_state (
        key TEXT PRIMARY KEY,
        value INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS message_delivery (
        chat_id TEXT PRIMARY KEY,
        last_seq INTEGER NOT NULL
      );
    `);
  }

  async status() {
    const result = this.ctx.storage.sql
      .exec<{ ready: number }>("SELECT 1 AS ready")
      .one();
    return { ready: result.ready === 1, storage: "sqlite" };
  }

  async notify(event: NotificationEvent): Promise<Notification> {
    return this.record(event, pushTextFor(event));
  }

  /**
   * Keeps one card for each chat, so a newer message replaces the earlier one.
   * The preview goes only to the push, never into the inbox.
   */
  async notifyMessage(
    chatId: string,
    preview: string,
    seq?: number,
  ): Promise<Notification | null> {
    const notification = this.ctx.storage.transactionSync(() => {
      // Older room instances may omit seq during a rolling deployment.
      if (seq !== undefined) {
        const previous = this.ctx.storage.sql
          .exec<{ last_seq: number }>(
            "SELECT last_seq FROM message_delivery WHERE chat_id = ?",
            chatId,
          )
          .toArray()[0];
        if (previous && previous.last_seq >= seq) return null;
        this.ctx.storage.sql.exec(
          "INSERT INTO message_delivery (chat_id, last_seq) VALUES (?, ?) ON CONFLICT (chat_id) DO UPDATE SET last_seq = excluded.last_seq",
          chatId,
          seq,
        );
      }
      this.deleteChatNotices(chatId);
      return this.save({ kind: "message", chatId });
    });
    if (!notification) return null;
    return this.announce(notification, {
      title: "New message",
      body: preview,
      group: chatId,
    });
  }

  /** Removes a chat's card once its messages are read. */
  async dismissChat(
    chatId: string,
    throughSeq?: number,
  ): Promise<{ unreadCount: number }> {
    const delivered = this.ctx.storage.sql
      .exec<{ last_seq: number }>(
        "SELECT last_seq FROM message_delivery WHERE chat_id = ?",
        chatId,
      )
      .toArray()[0];
    if (
      throughSeq === undefined ||
      !delivered ||
      delivered.last_seq <= throughSeq
    ) {
      this.deleteChatNotices(chatId);
    }
    return { unreadCount: this.unreadCount() };
  }

  private async record(
    event: NotificationEvent,
    push: PushText | null,
  ): Promise<Notification> {
    return this.announce(this.save(event), push);
  }

  private save(event: NotificationEvent): Notification {
    const notification: Notification = {
      ...event,
      id: crypto.randomUUID(),
      createdAt: new Date().toISOString(),
    };
    this.ctx.storage.sql.exec(
      "INSERT INTO notification (id, event, created_at) VALUES (?, ?, ?)",
      notification.id,
      JSON.stringify(event),
      Date.parse(notification.createdAt),
    );
    this.ctx.storage.sql.exec(
      "DELETE FROM notification WHERE id NOT IN (SELECT id FROM notification ORDER BY created_at DESC LIMIT ?)",
      inboxRetained,
    );
    return notification;
  }

  private async announce(
    notification: Notification,
    push: PushText | null,
  ): Promise<Notification> {
    const unreadCount = this.unreadCount();
    const message = JSON.stringify({
      type: "notification",
      notification,
      unreadCount,
    });
    this.broadcast(message);
    if (push) await this.push(notification, unreadCount, push);
    return notification;
  }

  /** Pushes a live chat update to open sockets. Not kept in the inbox. */
  async announceChatActivity(activity: ChatActivity) {
    const message = JSON.stringify({ type: "chat_activity", activity });
    this.broadcast(message);
  }

  private broadcast(message: string) {
    for (const socket of this.ctx.getWebSockets()) {
      try {
        socket.send(message);
      } catch {
        try {
          socket.close(1011, "delivery_failed");
        } catch {
          /* Already disconnected. */
        }
      }
    }
  }

  async pushStatus() {
    const devices = this.ctx.storage.sql
      .exec<{ count: number }>("SELECT COUNT(*) AS count FROM push_device")
      .one();
    const topic = this.env.APPLE_APP_ID.split(".").slice(1).join(".") || null;
    return {
      providerConfigured: this.pushSender !== null,
      registeredDeviceCount: devices.count,
      topic,
    };
  }

  async listNotifications(): Promise<Notification[]> {
    return this.ctx.storage.sql
      .exec<NotificationRow>(
        "SELECT id, event, created_at FROM notification ORDER BY created_at DESC LIMIT ?",
        inboxPageSize,
      )
      .toArray()
      .map((row) => ({
        ...(JSON.parse(row.event) as NotificationEvent),
        id: row.id,
        createdAt: new Date(row.created_at).toISOString(),
      }));
  }

  async inbox(): Promise<{
    notifications: Notification[];
    unreadCount: number;
  }> {
    return {
      notifications: await this.listNotifications(),
      unreadCount: this.unreadCount(),
    };
  }

  /** Everything in the inbox now counts as seen. */
  async markSeen(): Promise<{ unreadCount: number }> {
    const latest = this.ctx.storage.sql
      .exec<{ latest: number | null }>(
        "SELECT MAX(created_at) AS latest FROM notification",
      )
      .one().latest;
    this.ctx.storage.sql.exec(
      "INSERT INTO inbox_state (key, value) VALUES ('seen_through', ?) ON CONFLICT (key) DO UPDATE SET value = MAX(value, excluded.value)",
      latest ?? 0,
    );
    return { unreadCount: this.unreadCount() };
  }

  /** Returns false when no notification has that ID. */
  async deleteNotification(
    id: string,
  ): Promise<{ deleted: boolean; unreadCount: number }> {
    const cursor = this.ctx.storage.sql.exec(
      "DELETE FROM notification WHERE id = ?",
      id,
    );
    return {
      deleted: cursor.rowsWritten > 0,
      unreadCount: this.unreadCount(),
    };
  }

  async clearNotifications(): Promise<{ unreadCount: number }> {
    this.ctx.storage.sql.exec("DELETE FROM notification");
    return { unreadCount: 0 };
  }

  /** Keeps the newest few devices, so a person's old phones age out. */
  async registerDevice(token: string, environment: PushEnvironment) {
    this.ctx.storage.sql.exec(
      "INSERT INTO push_device (token, environment, updated_at) VALUES (?, ?, ?) ON CONFLICT (token) DO UPDATE SET environment = excluded.environment, updated_at = excluded.updated_at",
      token,
      environment,
      Date.now(),
    );
    this.ctx.storage.sql.exec(
      "DELETE FROM push_device WHERE token NOT IN (SELECT token FROM push_device ORDER BY updated_at DESC LIMIT ?)",
      devicesRetained,
    );
  }

  async unregisterDevice(token: string) {
    this.ctx.storage.sql.exec("DELETE FROM push_device WHERE token = ?", token);
  }

  async listDevices(): Promise<{ token: string; environment: string }[]> {
    return this.ctx.storage.sql
      .exec<DeviceRow>("SELECT token, environment FROM push_device")
      .toArray()
      .map(({ token, environment }) => ({ token, environment }));
  }

  /** Accepts a notification socket. The Worker checks the ticket before forwarding. */
  async fetch(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade") !== "websocket") {
      return new Response("Expected a WebSocket upgrade", { status: 426 });
    }
    const { 0: client, 1: server } = new WebSocketPair();
    this.ctx.acceptWebSocket(server);
    server.send(JSON.stringify({ type: "ready" }));
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(socket: WebSocket, message: string | ArrayBuffer) {
    if (message === "ping") socket.send(JSON.stringify({ type: "pong" }));
  }

  async webSocketClose(socket: WebSocket, code: number) {
    socket.close(reservedCloseCodes.has(code) ? 1000 : code);
  }

  private unreadCount(): number {
    const seenThrough =
      this.ctx.storage.sql
        .exec<{ value: number }>(
          "SELECT value FROM inbox_state WHERE key = 'seen_through'",
        )
        .toArray()[0]?.value ?? 0;
    return this.ctx.storage.sql
      .exec<{ count: number }>(
        "SELECT COUNT(*) AS count FROM notification WHERE created_at > ?",
        seenThrough,
      )
      .one().count;
  }

  private deleteChatNotices(chatId: string) {
    this.ctx.storage.sql.exec(
      "DELETE FROM notification WHERE json_extract(event, '$.kind') = 'message' AND json_extract(event, '$.chatId') = ?",
      chatId,
    );
  }

  /** A failed push never fails the event. The inbox already holds it. */
  private async push(
    notification: Notification,
    unreadCount: number,
    text: PushText,
  ) {
    const sender = this.pushSender;
    if (!sender) return;
    const data: Record<string, string> = {
      notificationId: notification.id,
      kind: notification.kind,
    };
    if ("connectionId" in notification) {
      data.connectionId = notification.connectionId;
    }
    if ("chatId" in notification) data.chatId = notification.chatId;
    const devices = this.ctx.storage.sql
      .exec<DeviceRow>("SELECT token, environment FROM push_device")
      .toArray();
    await Promise.all(
      devices.map(async (device) => {
        try {
          const result = await sender.send(device.token, device.environment, {
            ...text,
            badge: unreadCount,
            data,
          });
          if (result === "unregistered") {
            await this.unregisterDevice(device.token);
          }
        } catch (error) {
          console.warn(
            JSON.stringify({
              event: "apns_error",
              name: error instanceof Error ? error.name : "unknown",
            }),
          );
        }
      }),
    );
  }
}
