import { Hono } from "hono";
import { createMiddleware } from "hono/factory";
import { z } from "zod";
import type { AppEnv } from "../app-env";
import { recordEncounter } from "../connections/encounter";
import { createDatabase } from "../db/client";
import {
  deleteAllConnections,
  deleteAllPosts,
  endChanceNow,
  listAllConnections,
  listDevUsers,
  usersExist,
} from "../dev/dev-store";
import { createSeedPosts } from "../dev/seed-posts";
import { createSeedUsers, seedPassword } from "../dev/seed-users";
import { listInterests } from "../interests/interest-store";
import { coordinatorNotifier } from "../notifications/notification";

const encounterRequest = z
  .object({ firstUserId: z.string().min(1), secondUserId: z.string().min(1) })
  .refine((request) => request.firstUserId !== request.secondUserId);

/** Hides every dev route unless `DEV_TOOLS` is "true". */
const requireDevTools = createMiddleware<AppEnv>(async (context, next) => {
  if (context.env.DEV_TOOLS !== "true") {
    return context.json({ error: "not_found" }, 404);
  }
  await next();
});

/**
 * Local testing tools. Encounters made here are simulated and prove nothing
 * about physical proximity.
 */
export const devRoutes = new Hono<AppEnv>()
  .use(requireDevTools)
  .post("/seed", async (context) => {
    const userIds = await createSeedUsers(
      createDatabase(context.env),
      new Date(),
    );
    return context.json({ userIds, password: seedPassword });
  })
  // Seeds the people first, since the posts need their interests.
  .post("/forums/seed", async (context) => {
    const db = createDatabase(context.env);
    const now = new Date();
    await createSeedUsers(db, now);
    return context.json({ postIds: await createSeedPosts(db, now) });
  })
  .get("/users", async (context) =>
    context.json({
      seedPassword,
      users: await listDevUsers(createDatabase(context.env)),
    }),
  )
  .get("/interests", async (context) =>
    context.json({
      interests: await listInterests(createDatabase(context.env)),
    }),
  )
  .get("/users/:id/notifications", async (context) => {
    const coordinator = context.env.USER_COORDINATORS.getByName(
      context.req.param("id"),
    );
    return context.json({
      notifications: await coordinator.listNotifications(),
    });
  })
  .post("/encounters", async (context) => {
    const request = encounterRequest.safeParse(
      await context.req.json().catch(() => undefined),
    );
    if (!request.success) {
      return context.json({ error: "invalid_request" }, 400);
    }
    const { firstUserId, secondUserId } = request.data;
    const db = createDatabase(context.env);
    if (!(await usersExist(db, [firstUserId, secondUserId]))) {
      return context.json({ error: "user_not_found" }, 404);
    }
    const outcome = await recordEncounter(
      db,
      coordinatorNotifier(context.env),
      firstUserId,
      secondUserId,
      new Date(),
    );
    return context.json({
      simulated: true,
      outcome: outcome.kind,
      connection: "connection" in outcome ? outcome.connection : null,
    });
  })
  .get("/connections", async (context) =>
    context.json({
      connections: await listAllConnections(createDatabase(context.env)),
    }),
  )
  .post("/connections/:id/expire", async (context) => {
    const ended = await endChanceNow(
      createDatabase(context.env),
      context.req.param("id"),
    );
    if (!ended) return context.json({ error: "not_pending" }, 409);
    return context.json({ connection: ended });
  })
  .post("/reset", async (context) => {
    const db = createDatabase(context.env);
    await deleteAllConnections(db);
    await deleteAllPosts(db);
    return context.json({ ok: true });
  });
