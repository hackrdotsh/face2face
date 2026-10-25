import { DurableObject } from "cloudflare:workers";
import { otherSide } from "../connections/pair";
import type { ConnectionSide } from "../db/schema";
import {
  type ChatAccess,
  type ChatError,
  type ChatImage,
  type ChatMessage,
  clientFrame,
  imageVariantNames,
  type MessagePage,
  type SendFrame,
  type ServerFrame,
  type StoredImageVariants,
  type TypingState,
} from "./chat-types";
import { chatImageKey, mediaSecret, signMediaPath } from "./media-path";

export const chatAccessHeader = "x-chat-access";
export const defaultPageSize = 50;
export const maxPageSize = 100;
const chatClosedCode = 4000;
const reservedCloseCodes = new Set([1005, 1006, 1015]);

interface SocketState {
  side: ConnectionSide;
  isTyping: boolean;
}

interface MessageRow extends Record<string, SqlStorageValue> {
  seq: number;
  id: string;
  sender_side: ConnectionSide;
  client_id: string;
  text: string | null;
  image_id: string | null;
  image_variants: string | null;
  created_at: number;
}

const selectMessages = `
  SELECT message.*, image.variants AS image_variants
  FROM message LEFT JOIN image ON image.id = message.image_id
`;

/**
 * One per connection. Keeps the chat's messages, images, and each side's read
 * position, and relays messages and typing between the two people's sockets.
 * The Worker checks that a caller belongs to the chat before calling in.
 */
export class ChatRoom extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS room (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        connection_id TEXT NOT NULL,
        closed_at INTEGER
      );
      CREATE TABLE IF NOT EXISTS member (
        side TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        last_read_seq INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE IF NOT EXISTS image (
        id TEXT PRIMARY KEY,
        uploader_side TEXT NOT NULL,
        variants TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS message (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        id TEXT NOT NULL UNIQUE,
        sender_side TEXT NOT NULL,
        client_id TEXT NOT NULL,
        text TEXT,
        image_id TEXT REFERENCES image(id),
        created_at INTEGER NOT NULL,
        UNIQUE (sender_side, client_id)
      );
    `);
  }

  /** Newest messages first by page, oldest first within a page. */
  async listMessages(
    access: ChatAccess,
    before: string | null,
    limit: number,
  ): Promise<MessagePage> {
    this.rememberMembers(access);
    const beforeSeq = before ? this.findSeq(before) : null;
    if (before && beforeSeq === null) return { messages: [], hasMore: false };
    const rows = this.ctx.storage.sql
      .exec<MessageRow>(
        `${selectMessages} WHERE message.seq < ? ORDER BY message.seq DESC LIMIT ?`,
        beforeSeq ?? Number.MAX_SAFE_INTEGER,
        limit + 1,
      )
      .toArray();
    const page = rows.slice(0, limit).reverse();
    return {
      messages: await Promise.all(
        page.map((row) => this.viewMessage(row, access.side)),
      ),
      hasMore: rows.length > limit,
    };
  }

  async summarize(
    access: ChatAccess,
  ): Promise<{ lastMessage: ChatMessage | null; unreadCount: number }> {
    this.rememberMembers(access);
    const last = this.ctx.storage.sql
      .exec<MessageRow>(`${selectMessages} ORDER BY message.seq DESC LIMIT 1`)
      .toArray()[0];
    const unread = this.ctx.storage.sql
      .exec<{ count: number }>(
        `SELECT COUNT(*) AS count FROM message
         WHERE sender_side <> ?
           AND seq > (SELECT last_read_seq FROM member WHERE side = ?)`,
        access.side,
        access.side,
      )
      .one();
    return {
      lastMessage: last ? await this.viewMessage(last, access.side) : null,
      unreadCount: unread.count,
    };
  }

  /** Registers an uploaded image. Only its uploader can attach it to a message. */
  async addImage(
    access: ChatAccess,
    imageId: string,
    variants: StoredImageVariants,
  ): Promise<ChatImage> {
    this.rememberMembers(access);
    this.ctx.storage.sql.exec(
      "INSERT INTO image (id, uploader_side, variants, created_at) VALUES (?, ?, ?, ?)",
      imageId,
      access.side,
      JSON.stringify(variants),
      Date.now(),
    );
    return this.viewImage(access.connectionId, imageId, variants);
  }

  /** Ends the chat for both people and disconnects them. Messages stay stored. */
  async close(): Promise<void> {
    this.ctx.storage.sql.exec(
      "UPDATE room SET closed_at = COALESCE(closed_at, ?)",
      Date.now(),
    );
    for (const socket of this.ctx.getWebSockets()) {
      sendFrame(socket, { type: "closed" });
      socket.close(chatClosedCode, "chat_closed");
    }
  }

  /** Accepts a chat socket. The Worker sets the access header after its checks. */
  async fetch(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade") !== "websocket") {
      return new Response("Expected a WebSocket upgrade", { status: 426 });
    }
    const access = JSON.parse(
      request.headers.get(chatAccessHeader) ?? "null",
    ) as ChatAccess | null;
    if (!access) return new Response("Missing chat access", { status: 400 });
    this.rememberMembers(access);
    if (this.isClosed()) {
      return Response.json({ error: "chat_closed" }, { status: 410 });
    }
    const { 0: client, 1: server } = new WebSocketPair();
    this.ctx.acceptWebSocket(server, [access.side]);
    server.serializeAttachment({
      side: access.side,
      isTyping: false,
    } satisfies SocketState);
    sendFrame(server, { type: "ready" });
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(socket: WebSocket, message: string | ArrayBuffer) {
    if (message === "ping") return sendFrame(socket, { type: "pong" });
    const frame = clientFrame.safeParse(parseJSON(message));
    if (!frame.success) {
      return sendFrame(socket, { type: "error", error: "invalid_frame" });
    }
    const state = socketState(socket);
    switch (frame.data.type) {
      case "send":
        return this.handleSend(socket, state, frame.data);
      case "typing":
        return this.handleTyping(socket, state, frame.data.state);
      case "read":
        return this.handleRead(socket, state, frame.data.messageId);
    }
  }

  async webSocketClose(socket: WebSocket, code: number) {
    socket.close(reservedCloseCodes.has(code) ? 1000 : code);
    const state = socketState(socket);
    if (state.isTyping) this.announceTypingStopped(state.side, socket);
  }

  private async handleSend(
    socket: WebSocket,
    state: SocketState,
    frame: SendFrame,
  ) {
    const fail = (error: ChatError) =>
      sendFrame(socket, { type: "error", error, clientId: frame.clientId });
    if (this.isClosed()) return fail("chat_closed");
    if (frame.imageId && !this.isOwnImage(frame.imageId, state.side)) {
      return fail("image_not_found");
    }
    const { row, isNew } = this.insertMessage(state.side, frame);
    const viewForSender = await this.viewMessage(row, state.side);
    sendFrame(socket, {
      type: "ack",
      clientId: frame.clientId,
      message: viewForSender,
    });
    if (!isNew) return;
    this.markRead(state.side, row.seq);
    if (state.isTyping) {
      this.setTyping(socket, state, false);
      this.announceTypingStopped(state.side, socket);
    }
    await this.broadcastMessage(row, socket);
    await this.announceActivity(otherSide(state.side), row);
  }

  private handleTyping(
    socket: WebSocket,
    state: SocketState,
    typing: TypingState,
  ) {
    if (this.isClosed()) return;
    const isTyping = typing === "started";
    this.setTyping(socket, state, isTyping);
    if (isTyping) {
      this.sendToSide(otherSide(state.side), {
        type: "typing",
        state: "started",
      });
    } else {
      this.announceTypingStopped(state.side, socket);
    }
  }

  private handleRead(socket: WebSocket, state: SocketState, messageId: string) {
    const seq = this.findSeq(messageId);
    if (seq === null) {
      return sendFrame(socket, { type: "error", error: "message_not_found" });
    }
    this.markRead(state.side, seq);
  }

  /** Inserting the same client ID twice returns the first message. */
  private insertMessage(
    side: ConnectionSide,
    frame: SendFrame,
  ): { row: MessageRow; isNew: boolean } {
    const id = crypto.randomUUID();
    this.ctx.storage.sql.exec(
      `INSERT INTO message (id, sender_side, client_id, text, image_id, created_at)
       VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT (sender_side, client_id) DO NOTHING`,
      id,
      side,
      frame.clientId,
      frame.text?.trim() || null,
      frame.imageId ?? null,
      Date.now(),
    );
    const row = this.ctx.storage.sql
      .exec<MessageRow>(
        `${selectMessages} WHERE message.sender_side = ? AND message.client_id = ?`,
        side,
        frame.clientId,
      )
      .one();
    return { row, isNew: row.id === id };
  }

  private async broadcastMessage(row: MessageRow, senderSocket: WebSocket) {
    const views = {
      low: await this.viewMessage(row, "low"),
      high: await this.viewMessage(row, "high"),
    };
    for (const socket of this.ctx.getWebSockets()) {
      if (socket === senderSocket) continue;
      sendFrame(socket, {
        type: "message",
        message: views[socketState(socket).side],
      });
    }
  }

  /** Tells the recipient's other screens that the chat changed. Holds no content. */
  private async announceActivity(recipient: ConnectionSide, row: MessageRow) {
    const userId = this.memberUserId(recipient);
    const connectionId = this.connectionId();
    if (!userId || !connectionId) return;
    try {
      await this.env.USER_COORDINATORS.getByName(userId).announceChatActivity({
        chatId: connectionId,
        messageId: row.id,
        createdAt: new Date(row.created_at).toISOString(),
      });
    } catch (error) {
      console.error(
        JSON.stringify({
          event: "chat_activity_failed",
          name: error instanceof Error ? error.name : "unknown",
        }),
      );
    }
  }

  /** The other side sees "stopped" only once none of this side's sockets is typing. */
  private announceTypingStopped(side: ConnectionSide, closing: WebSocket) {
    const stillTyping = this.ctx
      .getWebSockets(side)
      .some((socket) => socket !== closing && socketState(socket).isTyping);
    if (stillTyping) return;
    this.sendToSide(otherSide(side), { type: "typing", state: "stopped" });
  }

  private sendToSide(side: ConnectionSide, frame: ServerFrame) {
    for (const socket of this.ctx.getWebSockets(side)) sendFrame(socket, frame);
  }

  private setTyping(socket: WebSocket, state: SocketState, isTyping: boolean) {
    state.isTyping = isTyping;
    socket.serializeAttachment(state);
  }

  private markRead(side: ConnectionSide, seq: number) {
    this.ctx.storage.sql.exec(
      "UPDATE member SET last_read_seq = MAX(last_read_seq, ?) WHERE side = ?",
      seq,
      side,
    );
  }

  private rememberMembers(access: ChatAccess) {
    this.ctx.storage.sql.exec(
      "INSERT INTO room (id, connection_id) VALUES (1, ?) ON CONFLICT (id) DO NOTHING",
      access.connectionId,
    );
    this.ctx.storage.sql.exec(
      `INSERT INTO member (side, user_id) VALUES ('low', ?), ('high', ?)
       ON CONFLICT (side) DO NOTHING`,
      access.lowUserId,
      access.highUserId,
    );
  }

  private isClosed(): boolean {
    return (
      this.ctx.storage.sql
        .exec<{ closed: number }>(
          "SELECT COUNT(*) AS closed FROM room WHERE closed_at IS NOT NULL",
        )
        .one().closed > 0
    );
  }

  private connectionId(): string | null {
    return (
      this.ctx.storage.sql
        .exec<{ connection_id: string }>("SELECT connection_id FROM room")
        .toArray()[0]?.connection_id ?? null
    );
  }

  private memberUserId(side: ConnectionSide): string | null {
    return (
      this.ctx.storage.sql
        .exec<{ user_id: string }>(
          "SELECT user_id FROM member WHERE side = ?",
          side,
        )
        .toArray()[0]?.user_id ?? null
    );
  }

  private findSeq(messageId: string): number | null {
    return (
      this.ctx.storage.sql
        .exec<{ seq: number }>(
          "SELECT seq FROM message WHERE id = ?",
          messageId,
        )
        .toArray()[0]?.seq ?? null
    );
  }

  private isOwnImage(imageId: string, side: ConnectionSide): boolean {
    return (
      this.ctx.storage.sql
        .exec(
          "SELECT 1 FROM image WHERE id = ? AND uploader_side = ?",
          imageId,
          side,
        )
        .toArray().length > 0
    );
  }

  private async viewMessage(
    row: MessageRow,
    viewer: ConnectionSide,
  ): Promise<ChatMessage> {
    const isOwn = row.sender_side === viewer;
    const connectionId = this.connectionId();
    return {
      id: row.id,
      clientId: isOwn ? row.client_id : null,
      from: isOwn ? "you" : "them",
      text: row.text,
      image:
        row.image_id && row.image_variants && connectionId
          ? await this.viewImage(
              connectionId,
              row.image_id,
              JSON.parse(row.image_variants) as StoredImageVariants,
            )
          : null,
      createdAt: new Date(row.created_at).toISOString(),
    };
  }

  private async viewImage(
    connectionId: string,
    imageId: string,
    variants: StoredImageVariants,
  ): Promise<ChatImage> {
    const secret = mediaSecret(this.env);
    const now = new Date();
    const [original, preview, thumb] = await Promise.all(
      imageVariantNames.map(async (name) => ({
        ...variants[name],
        path: await signMediaPath(
          secret,
          chatImageKey(connectionId, imageId, name),
          now,
        ),
      })),
    );
    if (!original || !preview || !thumb) throw new Error("Missing variant");
    return { id: imageId, variants: { original, preview, thumb } };
  }
}

function socketState(socket: WebSocket): SocketState {
  return socket.deserializeAttachment() as SocketState;
}

function sendFrame(socket: WebSocket, frame: ServerFrame) {
  socket.send(JSON.stringify(frame));
}

function parseJSON(message: string | ArrayBuffer): unknown {
  if (typeof message !== "string") return undefined;
  try {
    return JSON.parse(message);
  } catch {
    return undefined;
  }
}
