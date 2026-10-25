import { Hono } from "hono";
import { bodyLimit } from "hono/body-limit";
import { createMiddleware } from "hono/factory";
import { z } from "zod";
import type { AppEnv } from "../app-env";
import { findChatAccess } from "../chats/chat-access";
import { maxImageUploadBytes, storeChatImage } from "../chats/chat-images";
import {
  chatAccessHeader,
  defaultPageSize,
  maxPageSize,
} from "../chats/chat-room";
import type { ChatAccess } from "../chats/chat-types";
import { getChatSummary, listChatSummaries } from "../chats/chats";
import { createDatabase } from "../db/client";
import { requireOnboarded, requireSession } from "../middleware/session";
import {
  createSocketTicket,
  readSocketTicket,
  socketTicketSecret,
} from "../notifications/socket-ticket";

interface ChatEnv extends AppEnv {
  Variables: AppEnv["Variables"] & { chat: ChatAccess };
}

const pageQuery = z.object({
  before: z.string().min(1).optional(),
  limit: z.coerce
    .number()
    .int()
    .min(1)
    .max(maxPageSize)
    .default(defaultPageSize),
});

/** Answers 404 unless the person can chat on this connection. */
const requireChat = createMiddleware<ChatEnv>(async (context, next) => {
  const access = await findChatAccess(
    createDatabase(context.env),
    context.req.param("id") ?? "",
    context.var.user.id,
  );
  if (!access) return context.json({ error: "not_found" }, 404);
  context.set("chat", access);
  await next();
});

const imageBodyLimit = bodyLimit({
  maxSize: maxImageUploadBytes,
  onError: (context) => context.json({ error: "image_too_large" }, 413),
});

export const chatRoutes = new Hono<ChatEnv>()
  .get("/", requireSession, requireOnboarded, async (context) =>
    context.json({
      chats: await listChatSummaries(
        createDatabase(context.env),
        context.env.CHAT_ROOMS,
        context.var.user.id,
        new Date(),
      ),
    }),
  )
  .get("/:id", requireSession, requireOnboarded, async (context) => {
    const chat = await getChatSummary(
      createDatabase(context.env),
      context.env.CHAT_ROOMS,
      context.var.user.id,
      context.req.param("id"),
      new Date(),
    );
    if (!chat) return context.json({ error: "not_found" }, 404);
    return context.json({ chat });
  })
  .get(
    "/:id/messages",
    requireSession,
    requireOnboarded,
    requireChat,
    async (context) => {
      const query = pageQuery.safeParse(context.req.query());
      if (!query.success) {
        return context.json({ error: "invalid_request" }, 400);
      }
      const access = context.var.chat;
      return context.json(
        await context.env.CHAT_ROOMS.getByName(
          access.connectionId,
        ).listMessages(access, query.data.before ?? null, query.data.limit),
      );
    },
  )
  .post(
    "/:id/ticket",
    requireSession,
    requireOnboarded,
    requireChat,
    async (context) =>
      context.json(
        await createSocketTicket(
          socketTicketSecret(context.env),
          context.var.user.id,
          new Date(),
        ),
      ),
  )
  .post(
    "/:id/images",
    imageBodyLimit,
    requireSession,
    requireOnboarded,
    requireChat,
    async (context) => {
      const form = await context.req.formData().catch(() => null);
      const upload = form?.get("image");
      if (!(upload instanceof File)) {
        return context.json({ error: "invalid_request" }, 400);
      }
      const access = context.var.chat;
      const imageId = crypto.randomUUID();
      const stored = await storeChatImage(
        context.env,
        access.connectionId,
        imageId,
        await upload.arrayBuffer(),
      );
      if (!stored.ok) return context.json({ error: stored.error }, 415);
      const image = await context.env.CHAT_ROOMS.getByName(
        access.connectionId,
      ).addImage(access, imageId, stored.variants);
      return context.json({ image }, 201);
    },
  )
  .get("/:id/socket", async (context) => {
    if (context.req.header("Upgrade") !== "websocket") {
      return context.json({ error: "websocket_required" }, 426);
    }
    const userId = await readSocketTicket(
      socketTicketSecret(context.env),
      context.req.query("ticket") ?? "",
      new Date(),
    );
    if (!userId) return context.json({ error: "unauthorized" }, 401);
    const access = await findChatAccess(
      createDatabase(context.env),
      context.req.param("id"),
      userId,
    );
    if (!access) return context.json({ error: "not_found" }, 404);
    const headers = new Headers(context.req.raw.headers);
    headers.set(chatAccessHeader, JSON.stringify(access));
    return context.env.CHAT_ROOMS.getByName(access.connectionId).fetch(
      new Request(context.req.raw, { headers }),
    );
  });
