import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../app-env";
import { createDatabase } from "../db/client";
import { requireOnboarded, requireSession } from "../middleware/session";
import {
  claimPushDevice,
  releasePushDevice,
} from "../notifications/push-devices";
import {
  createSocketTicket,
  readSocketTicket,
  socketTicketSecret,
} from "../notifications/socket-ticket";

/** APNs device tokens are hex. Current ones are 32 bytes; Apple allows up to 100. */
const deviceToken = z
  .string()
  .regex(/^[0-9a-f]{64,200}$/i)
  .transform((token) => token.toLowerCase());
const deviceBody = z.object({ environment: z.enum(["sandbox", "production"]) });

export const notificationRoutes = new Hono<AppEnv>()
  .get("/push-status", requireSession, requireOnboarded, async (context) =>
    context.json(
      await context.env.USER_COORDINATORS.getByName(
        context.var.user.id,
      ).pushStatus(),
    ),
  )
  .get("/", requireSession, requireOnboarded, async (context) =>
    context.json(
      await context.env.USER_COORDINATORS.getByName(
        context.var.user.id,
      ).inbox(),
    ),
  )
  .delete("/", requireSession, requireOnboarded, async (context) =>
    context.json(
      await context.env.USER_COORDINATORS.getByName(
        context.var.user.id,
      ).clearNotifications(),
    ),
  )
  .post("/seen", requireSession, requireOnboarded, async (context) =>
    context.json(
      await context.env.USER_COORDINATORS.getByName(
        context.var.user.id,
      ).markSeen(),
    ),
  )
  .put("/devices/:token", requireSession, requireOnboarded, async (context) => {
    const token = deviceToken.safeParse(context.req.param("token"));
    const body = deviceBody.safeParse(
      await context.req.json().catch(() => null),
    );
    if (!token.success || !body.success) {
      return context.json({ error: "invalid_device" }, 400);
    }
    await claimPushDevice(
      context.env,
      createDatabase(context.env),
      context.var.user.id,
      token.data,
      body.data.environment,
      new Date(),
    );
    return context.body(null, 204);
  })
  .delete("/devices/:token", requireSession, async (context) => {
    const token = deviceToken.safeParse(context.req.param("token"));
    if (!token.success) return context.json({ error: "invalid_device" }, 400);
    await releasePushDevice(
      context.env,
      createDatabase(context.env),
      context.var.user.id,
      token.data,
    );
    return context.body(null, 204);
  })
  .post("/ticket", requireSession, requireOnboarded, async (context) =>
    context.json(
      await createSocketTicket(
        socketTicketSecret(context.env),
        context.var.user.id,
        new Date(),
      ),
    ),
  )
  .get("/socket", async (context) => {
    if (context.req.header("Upgrade") !== "websocket") {
      return context.json({ error: "websocket_required" }, 426);
    }
    const userId = await readSocketTicket(
      socketTicketSecret(context.env),
      context.req.query("ticket") ?? "",
      new Date(),
    );
    if (!userId) return context.json({ error: "unauthorized" }, 401);
    return context.env.USER_COORDINATORS.getByName(userId).fetch(
      context.req.raw,
    );
  })
  .delete("/:id", requireSession, requireOnboarded, async (context) => {
    const result = await context.env.USER_COORDINATORS.getByName(
      context.var.user.id,
    ).deleteNotification(context.req.param("id"));
    if (!result.deleted) return context.json({ error: "not_found" }, 404);
    return context.json({ unreadCount: result.unreadCount });
  });
