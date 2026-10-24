import { DurableObject } from "cloudflare:workers";
import type {
  Notification,
  NotificationEvent,
} from "./notifications/notification";

const inboxPageSize = 50;
const inboxRetained = 200;
const reservedCloseCodes = new Set([1005, 1006, 1015]);

interface NotificationRow extends Record<string, SqlStorageValue> {
  id: string;
  event: string;
  created_at: number;
}

/**
 * One per person. Keeps their notification inbox and pushes new notifications
 * to their open sockets. The inbox is the record; a socket only delivers live
 * updates while a client is in the foreground.
 */
export class UserCoordinator extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS notification (
        id TEXT PRIMARY KEY,
        event TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    `);
  }

  async status() {
    const result = this.ctx.storage.sql
      .exec<{ ready: number }>("SELECT 1 AS ready")
      .one();
    return { ready: result.ready === 1, storage: "sqlite" };
  }

  async notify(event: NotificationEvent): Promise<Notification> {
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
    const message = JSON.stringify({ type: "notification", notification });
    for (const socket of this.ctx.getWebSockets()) socket.send(message);
    return notification;
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
}
