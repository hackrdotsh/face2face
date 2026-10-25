import { type Context, Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../app-env";
import {
  blockConnection,
  type ConnectionActionResult,
  decideConnection,
  goPublic,
  listConnectionViews,
} from "../connections/connections";
import { createDatabase } from "../db/client";
import { connectionDecisions } from "../db/schema";
import { requireOnboarded, requireSession } from "../middleware/session";
import { coordinatorNotifier } from "../notifications/notification";

const decisionRequest = z.object({ decision: z.enum(connectionDecisions) });

export const connectionRoutes = new Hono<AppEnv>()
  .use(requireSession, requireOnboarded)
  .get("/", async (context) =>
    context.json({
      connections: await listConnectionViews(
        createDatabase(context.env),
        context.var.user.id,
        new Date(),
      ),
    }),
  )
  .post("/:id/decision", async (context) => {
    const request = decisionRequest.safeParse(
      await context.req.json().catch(() => undefined),
    );
    if (!request.success)
      return context.json({ error: "invalid_request" }, 400);
    return respond(
      context,
      await decideConnection(
        createDatabase(context.env),
        coordinatorNotifier(context.env),
        context.var.user.id,
        context.req.param("id"),
        request.data.decision,
        new Date(),
      ),
    );
  })
  .post("/:id/public", async (context) =>
    respond(
      context,
      await goPublic(
        createDatabase(context.env),
        coordinatorNotifier(context.env),
        context.var.user.id,
        context.req.param("id"),
        new Date(),
      ),
    ),
  )
  .post("/:id/block", async (context) => {
    const result = await blockConnection(
      createDatabase(context.env),
      coordinatorNotifier(context.env),
      context.var.user.id,
      context.req.param("id"),
      new Date(),
    );
    if (result.ok) {
      await context.env.CHAT_ROOMS.getByName(result.connection.id).close();
    }
    return respond(context, result);
  });

function respond(context: Context<AppEnv>, result: ConnectionActionResult) {
  if (result.ok) return context.json({ connection: result.connection });
  if (result.error === "not_found")
    return context.json({ error: "not_found" }, 404);
  return context.json({ error: result.error }, 409);
}
