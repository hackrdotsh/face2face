import { Hono } from "hono";
import type { AppEnv } from "../app-env";
import { requireOnboarded, requireSession } from "../middleware/session";
import {
  createSocketTicket,
  readSocketTicket,
  socketTicketSecret,
} from "../notifications/socket-ticket";

export const notificationRoutes = new Hono<AppEnv>()
  .get("/", requireSession, requireOnboarded, async (context) => {
    const coordinator = context.env.USER_COORDINATORS.getByName(
      context.var.user.id,
    );
    return context.json({
      notifications: await coordinator.listNotifications(),
    });
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
  });
