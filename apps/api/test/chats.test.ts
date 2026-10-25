import { runInDurableObject } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { messagePreview } from "../src/chats/chat-room";
import type { PushAlert } from "../src/notifications/apns";
import { photoWithExif } from "./fixtures/photo-with-exif";
import {
  bearerHeaders,
  callAPI,
  nativeOrigin,
  postJSON,
  requireAuthToken,
} from "./helpers";

const ava = "seed-ava";
const ben = "seed-ben";
const noor = "seed-noor";

type Headers = Record<string, string>;

interface Variant {
  path: string;
  width: number;
  height: number;
}

interface ChatImage {
  id: string;
  variants: Record<"original" | "preview" | "thumb", Variant>;
}

interface ChatMessage {
  id: string;
  clientId: string | null;
  from: "you" | "them";
  text: string | null;
  image: ChatImage | null;
}

interface Frame {
  type: string;
  clientId?: string;
  message?: ChatMessage;
  state?: string;
  error?: string;
  activity?: { chatId: string; messageId: string };
}

interface ChatSummary {
  id: string;
  connection: { status: string; them: unknown };
  lastMessage: ChatMessage | null;
  unreadCount: number;
}

beforeEach(async () => {
  await env.DB.prepare("DELETE FROM rate_limit").run();
  await postJSON("/api/dev/reset", {});
  await postJSON("/api/dev/seed", {});
});

async function signInAs(userId: string): Promise<Headers> {
  const response = await postJSON("/api/auth/sign-in/email", {
    email: `${userId.replace("seed-", "")}@seed.face2face.test`,
    password: "face2face-seed-password",
  });
  return bearerHeaders(requireAuthToken(response));
}

async function encounter(firstUserId: string, secondUserId: string) {
  const response = await postJSON("/api/dev/encounters", {
    firstUserId,
    secondUserId,
  });
  const body = await response.json<{ connection: { id: string } }>();
  return body.connection.id;
}

/** Two people who met and both accepted, with a chat between them. */
async function connectedPair() {
  const [avaHeaders, benHeaders] = await Promise.all([
    signInAs(ava),
    signInAs(ben),
  ]);
  const chatId = await encounter(ava, ben);
  for (const headers of [avaHeaders, benHeaders]) {
    const response = await postJSON(
      `/api/connections/${chatId}/decision`,
      { decision: "accepted" },
      headers,
    );
    expect(response.status).toBe(200);
  }
  return { chatId, avaHeaders, benHeaders };
}

class TestSocket {
  readonly frames: Frame[] = [];
  closeCode: number | null = null;

  constructor(private readonly socket: WebSocket) {
    socket.addEventListener("message", (event) => {
      this.frames.push(JSON.parse(String(event.data)) as Frame);
    });
    socket.addEventListener("close", (event) => {
      this.closeCode = event.code;
    });
    socket.accept();
  }

  send(frame: unknown) {
    this.socket.send(typeof frame === "string" ? frame : JSON.stringify(frame));
  }

  close() {
    this.socket.close();
  }

  ofType(type: string) {
    return this.frames.filter((frame) => frame.type === type);
  }

  async waitFor(type: string, count = 1) {
    await expect
      .poll(() => this.ofType(type).length)
      .toBeGreaterThanOrEqual(count);
    return this.ofType(type)[count - 1] as Frame;
  }
}

async function upgrade(path: string) {
  const response = await callAPI(path, {
    headers: { Upgrade: "websocket", Origin: nativeOrigin },
  });
  if (!response.webSocket) {
    throw new Error(`No WebSocket in HTTP ${response.status}`);
  }
  const socket = new TestSocket(response.webSocket);
  await socket.waitFor("ready");
  return socket;
}

async function openChatSocket(headers: Headers, chatId: string) {
  const response = await postJSON(`/api/chats/${chatId}/ticket`, {}, headers);
  expect(response.status).toBe(200);
  const { ticket } = await response.json<{ ticket: string }>();
  return upgrade(
    `/api/chats/${chatId}/socket?ticket=${encodeURIComponent(ticket)}`,
  );
}

async function openNotificationSocket(headers: Headers) {
  const response = await postJSON("/api/notifications/ticket", {}, headers);
  const { ticket } = await response.json<{ ticket: string }>();
  return upgrade(
    `/api/notifications/socket?ticket=${encodeURIComponent(ticket)}`,
  );
}

async function listChats(headers: Headers) {
  const response = await callAPI("/api/chats", { headers });
  expect(response.status).toBe(200);
  return (await response.json<{ chats: ChatSummary[] }>()).chats;
}

async function listMessages(headers: Headers, chatId: string, query = "") {
  const response = await callAPI(`/api/chats/${chatId}/messages${query}`, {
    headers,
  });
  expect(response.status).toBe(200);
  return response.json<{ messages: ChatMessage[]; hasMore: boolean }>();
}

function uploadImage(
  headers: Headers,
  chatId: string,
  bytes: Uint8Array<ArrayBuffer>,
) {
  const form = new FormData();
  form.append("image", new File([bytes], "photo.jpg", { type: "image/jpeg" }));
  return callAPI(`/api/chats/${chatId}/images`, {
    method: "POST",
    headers,
    body: form,
  });
}

describe("chat access", () => {
  it("opens a chat only once both people accept", async () => {
    const avaHeaders = await signInAs(ava);
    const chatId = await encounter(ava, ben);
    expect(await listChats(avaHeaders)).toEqual([]);
    const pending = await callAPI(`/api/chats/${chatId}/messages`, {
      headers: avaHeaders,
    });
    expect(pending.status).toBe(404);
  });

  it("lists a new chat with no messages and nothing unread", async () => {
    const { chatId, avaHeaders } = await connectedPair();
    const [chat] = await listChats(avaHeaders);
    expect(chat).toMatchObject({
      id: chatId,
      connection: { status: "private", them: null },
      lastMessage: null,
      unreadCount: 0,
    });
  });

  it("hides the chat from anyone outside the connection", async () => {
    const { chatId } = await connectedPair();
    const noorHeaders = await signInAs(noor);
    for (const path of ["", "/messages"]) {
      const response = await callAPI(`/api/chats/${chatId}${path}`, {
        headers: noorHeaders,
      });
      expect(response.status).toBe(404);
    }
    const ticket = await postJSON(
      `/api/chats/${chatId}/ticket`,
      {},
      noorHeaders,
    );
    expect(ticket.status).toBe(404);
  });

  it("refuses a chat socket with a ticket for someone outside the chat", async () => {
    const { chatId } = await connectedPair();
    const ticketResponse = await postJSON(
      "/api/notifications/ticket",
      {},
      await signInAs(noor),
    );
    const { ticket } = await ticketResponse.json<{ ticket: string }>();
    const response = await callAPI(
      `/api/chats/${chatId}/socket?ticket=${encodeURIComponent(ticket)}`,
      { headers: { Upgrade: "websocket", Origin: nativeOrigin } },
    );
    expect(response.status).toBe(404);
  });
});

describe("live messages", () => {
  it("acks the sender and delivers to the other person without naming anyone", async () => {
    const { chatId, avaHeaders, benHeaders } = await connectedPair();
    const avaSocket = await openChatSocket(avaHeaders, chatId);
    const benSocket = await openChatSocket(benHeaders, chatId);

    avaSocket.send({ type: "send", clientId: "c-1", text: "  hello  " });
    const ack = await avaSocket.waitFor("ack");
    const delivered = await benSocket.waitFor("message");

    expect(ack.message).toMatchObject({
      clientId: "c-1",
      from: "you",
      text: "hello",
    });
    expect(delivered.message).toMatchObject({
      id: ack.message?.id,
      clientId: null,
      from: "them",
      text: "hello",
    });
    expect(JSON.stringify(delivered)).not.toContain(ava);
    expect(avaSocket.ofType("message")).toEqual([]);
  });

  it("stores a resent client ID once and acks it with the first message", async () => {
    const { chatId, avaHeaders, benHeaders } = await connectedPair();
    const avaSocket = await openChatSocket(avaHeaders, chatId);
    const benSocket = await openChatSocket(benHeaders, chatId);

    avaSocket.send({ type: "send", clientId: "same", text: "once" });
    avaSocket.send({ type: "send", clientId: "same", text: "once" });
    const second = await avaSocket.waitFor("ack", 2);
    const first = avaSocket.ofType("ack")[0];

    expect(second.message?.id).toBe(first?.message?.id);
    await benSocket.waitFor("message");
    expect(benSocket.ofType("message")).toHaveLength(1);
    expect((await listMessages(benHeaders, chatId)).messages).toHaveLength(1);
  });

  it("answers a bad frame with an error instead of closing", async () => {
    const { chatId, avaHeaders } = await connectedPair();
    const socket = await openChatSocket(avaHeaders, chatId);
    socket.send("not json");
    socket.send({ type: "send", clientId: "blank", text: "   " });
    await socket.waitFor("error", 2);
    expect(socket.ofType("error").map((frame) => frame.error)).toEqual([
      "invalid_frame",
      "invalid_frame",
    ]);
    socket.send("ping");
    await socket.waitFor("pong");
  });

  it("pages history newest first and counts unread until read", async () => {
    const { chatId, avaHeaders, benHeaders } = await connectedPair();
    const avaSocket = await openChatSocket(avaHeaders, chatId);
    for (const text of ["one", "two", "three"]) {
      avaSocket.send({ type: "send", clientId: text, text });
    }
    await avaSocket.waitFor("ack", 3);

    const latest = await listMessages(benHeaders, chatId, "?limit=2");
    expect(latest.messages.map((message) => message.text)).toEqual([
      "two",
      "three",
    ]);
    expect(latest.hasMore).toBe(true);
    const older = await listMessages(
      benHeaders,
      chatId,
      `?limit=2&before=${latest.messages[0]?.id}`,
    );
    expect(older.messages.map((message) => message.text)).toEqual(["one"]);
    expect(older.hasMore).toBe(false);

    expect((await listChats(benHeaders))[0]).toMatchObject({
      unreadCount: 3,
      lastMessage: { text: "three", from: "them" },
    });
    expect((await listChats(avaHeaders))[0]?.unreadCount).toBe(0);

    const benSocket = await openChatSocket(benHeaders, chatId);
    benSocket.send({ type: "read", messageId: latest.messages[1]?.id });
    await expect
      .poll(async () => (await listChats(benHeaders))[0]?.unreadCount)
      .toBe(0);
  });

  it("pings the recipient's notification socket without message content", async () => {
    const { chatId, avaHeaders, benHeaders } = await connectedPair();
    const benNotifications = await openNotificationSocket(benHeaders);
    const avaSocket = await openChatSocket(avaHeaders, chatId);
    avaSocket.send({ type: "send", clientId: "c-1", text: "secret words" });
    const ack = await avaSocket.waitFor("ack");

    const activity = await benNotifications.waitFor("chat_activity");
    expect(activity.activity).toMatchObject({
      chatId,
      messageId: ack.message?.id,
    });
    expect(JSON.stringify(activity)).not.toContain("secret words");
    const inbox = await callAPI("/api/notifications", { headers: benHeaders });
    expect(JSON.stringify(await inbox.json())).not.toContain("chat_activity");
  });
});

describe("typing", () => {
  it("relays typing to the other person only", async () => {
    const { chatId, avaHeaders, benHeaders } = await connectedPair();
    const avaSocket = await openChatSocket(avaHeaders, chatId);
    const benSocket = await openChatSocket(benHeaders, chatId);

    avaSocket.send({ type: "typing", state: "started" });
    expect((await benSocket.waitFor("typing")).state).toBe("started");
    avaSocket.send({ type: "typing", state: "stopped" });
    expect((await benSocket.waitFor("typing", 2)).state).toBe("stopped");
    expect(avaSocket.ofType("typing")).toEqual([]);
  });

  it("stops typing when the person sends", async () => {
    const { chatId, avaHeaders, benHeaders } = await connectedPair();
    const avaSocket = await openChatSocket(avaHeaders, chatId);
    const benSocket = await openChatSocket(benHeaders, chatId);
    avaSocket.send({ type: "typing", state: "started" });
    await benSocket.waitFor("typing");
    avaSocket.send({ type: "send", clientId: "c-1", text: "hi" });
    expect((await benSocket.waitFor("typing", 2)).state).toBe("stopped");
  });

  it("stops typing when the typing socket disconnects", async () => {
    const { chatId, avaHeaders, benHeaders } = await connectedPair();
    const avaSocket = await openChatSocket(avaHeaders, chatId);
    const benSocket = await openChatSocket(benHeaders, chatId);
    avaSocket.send({ type: "typing", state: "started" });
    await benSocket.waitFor("typing");
    avaSocket.close();
    expect((await benSocket.waitFor("typing", 2)).state).toBe("stopped");
  });
});

describe("chat images", () => {
  it("strips metadata and stores three sizes", async () => {
    const { chatId, avaHeaders, benHeaders } = await connectedPair();
    const response = await uploadImage(avaHeaders, chatId, photoWithExif);
    expect(response.status).toBe(201);
    const { image } = await response.json<{ image: ChatImage }>();

    expect(image.variants.original).toMatchObject({
      width: 2048,
      height: 1024,
    });
    expect(image.variants.preview).toMatchObject({ width: 1024, height: 512 });
    expect(image.variants.thumb).toMatchObject({ width: 256, height: 128 });

    for (const variant of Object.values(image.variants)) {
      const served = await callAPI(variant.path);
      expect(served.status).toBe(200);
      expect(served.headers.get("Content-Type")).toBe("image/webp");
      expect(served.headers.get("Cross-Origin-Resource-Policy")).toBe(
        "cross-origin",
      );
      const text = new TextDecoder("latin1").decode(await served.arrayBuffer());
      expect(text.startsWith("RIFF")).toBe(true);
      expect(text).not.toContain("Exif");
      expect(text).not.toContain("f2f-exif-marker");
    }

    const avaSocket = await openChatSocket(avaHeaders, chatId);
    const benSocket = await openChatSocket(benHeaders, chatId);
    avaSocket.send({ type: "send", clientId: "img", imageId: image.id });
    const delivered = await benSocket.waitFor("message");
    expect(delivered.message?.image?.id).toBe(image.id);
    expect(delivered.message?.text).toBeNull();
  });

  it("lets only the uploader attach an image", async () => {
    const { chatId, avaHeaders, benHeaders } = await connectedPair();
    const response = await uploadImage(avaHeaders, chatId, photoWithExif);
    const { image } = await response.json<{ image: ChatImage }>();
    const benSocket = await openChatSocket(benHeaders, chatId);
    benSocket.send({ type: "send", clientId: "steal", imageId: image.id });
    expect((await benSocket.waitFor("error")).error).toBe("image_not_found");
  });

  it("rejects a file that is not an image", async () => {
    const { chatId, avaHeaders } = await connectedPair();
    const response = await uploadImage(
      avaHeaders,
      chatId,
      new TextEncoder().encode("<svg onload=alert(1)>"),
    );
    expect(response.status).toBe(415);
  });

  it("refuses a tampered or expired media path", async () => {
    const { chatId, avaHeaders } = await connectedPair();
    const response = await uploadImage(avaHeaders, chatId, photoWithExif);
    const { image } = await response.json<{ image: ChatImage }>();
    const path = image.variants.thumb.path;

    expect((await callAPI(path.replace("/thumb?", "/original?"))).status).toBe(
      403,
    );
    expect(
      (await callAPI(path.replace(/expires=\d+/, "expires=1000"))).status,
    ).toBe(403);
    expect((await callAPI(path.split("?")[0] ?? "")).status).toBe(403);
  });
});

describe("blocking", () => {
  it("disconnects both people and closes the chat", async () => {
    const { chatId, avaHeaders, benHeaders } = await connectedPair();
    const avaSocket = await openChatSocket(avaHeaders, chatId);
    const benSocket = await openChatSocket(benHeaders, chatId);

    const blocked = await postJSON(
      `/api/connections/${chatId}/block`,
      {},
      avaHeaders,
    );
    expect(blocked.status).toBe(200);
    await benSocket.waitFor("closed");
    await expect.poll(() => benSocket.closeCode).toBe(4000);
    await expect.poll(() => avaSocket.closeCode).toBe(4000);

    expect(await listChats(benHeaders)).toEqual([]);
    expect(await listChats(avaHeaders)).toEqual([]);
    const history = await callAPI(`/api/chats/${chatId}/messages`, {
      headers: avaHeaders,
    });
    expect(history.status).toBe(404);
  });
});

describe("message notifications", () => {
  interface Inbox {
    notifications: { id: string; kind: string; chatId?: string }[];
    unreadCount: number;
  }

  async function freshCoordinator(userId: string) {
    const alerts: PushAlert[] = [];
    await runInDurableObject(
      env.USER_COORDINATORS.getByName(userId),
      async (coordinator) => {
        await coordinator.clearNotifications();
        await coordinator.registerDevice("c".repeat(64), "sandbox");
        coordinator.pushSender = {
          async send(_token, _environment, alert) {
            alerts.push(alert);
            return "sent";
          },
        };
      },
    );
    return alerts;
  }

  async function inbox(headers: Headers) {
    const response = await callAPI("/api/notifications", { headers });
    return response.json<Inbox>();
  }

  async function send(socket: TestSocket, clientId: string, text: string) {
    const acks = socket.ofType("ack").length;
    socket.send({ type: "send", clientId, text });
    return (await socket.waitFor("ack", acks + 1)).message as ChatMessage;
  }

  it("leaves one card per chat and pushes a preview when the chat is closed", async () => {
    const { chatId, avaHeaders, benHeaders } = await connectedPair();
    await postJSON("/api/notifications/seen", {}, benHeaders);
    const alerts = await freshCoordinator(ben);
    const avaSocket = await openChatSocket(avaHeaders, chatId);

    await send(avaSocket, "m1", "Coffee tomorrow?\nI know a place.");
    await send(avaSocket, "m2", "Around 10?");
    await expect.poll(() => alerts.length).toBe(2);

    expect(alerts.map((alert) => alert.body)).toEqual([
      "Coffee tomorrow?",
      "Around 10?",
    ]);
    expect(alerts[1]).toMatchObject({
      title: "New message",
      group: chatId,
      badge: 1,
      data: { kind: "message", chatId },
    });
    expect(JSON.stringify(alerts)).not.toMatch(/seed-|Ava|Ben/);
    const { notifications, unreadCount } = await inbox(benHeaders);
    expect(notifications.filter((n) => n.kind === "message")).toEqual([
      expect.objectContaining({ kind: "message", chatId }),
    ]);
    expect(JSON.stringify(notifications)).not.toMatch(/Coffee|Around/);
    expect(unreadCount).toBe(1);
    avaSocket.close();
  });

  it("stays quiet while the recipient has the chat open", async () => {
    const { chatId, avaHeaders, benHeaders } = await connectedPair();
    const alerts = await freshCoordinator(ben);
    const benSocket = await openChatSocket(benHeaders, chatId);
    const avaSocket = await openChatSocket(avaHeaders, chatId);

    await send(avaSocket, "m1", "Hi there");
    await benSocket.waitFor("message");
    expect(alerts).toEqual([]);
    expect(
      (await inbox(benHeaders)).notifications.some((n) => n.kind === "message"),
    ).toBe(false);
    benSocket.close();
    avaSocket.close();
  });

  it("removes the card once the recipient reads the chat", async () => {
    const { chatId, avaHeaders, benHeaders } = await connectedPair();
    await freshCoordinator(ben);
    const avaSocket = await openChatSocket(avaHeaders, chatId);
    const message = await send(avaSocket, "m1", "Hello");
    await expect
      .poll(async () =>
        (await inbox(benHeaders)).notifications.some(
          (n) => n.kind === "message",
        ),
      )
      .toBe(true);

    const benSocket = await openChatSocket(benHeaders, chatId);
    benSocket.send({ type: "read", messageId: message.id });
    await expect
      .poll(async () =>
        (await inbox(benHeaders)).notifications.some(
          (n) => n.kind === "message",
        ),
      )
      .toBe(false);
    benSocket.close();
    avaSocket.close();
  });

  it("previews the first line, shortens long text, and names photos", () => {
    expect(messagePreview({ text: "  Hello\nthere " })).toBe("Hello");
    expect(messagePreview({ text: null })).toBe("Sent a photo");
    const long = messagePreview({ text: "a".repeat(300) });
    expect(long).toHaveLength(120);
    expect(long.endsWith("…")).toBe(true);
  });
});
