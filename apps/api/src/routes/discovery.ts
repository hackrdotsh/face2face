import { type Context, Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../app-env";
import { createDatabase } from "../db/client";
import {
  type DiscoveryResult,
  observePeer,
  rotateDiscovery,
  startDiscovery,
  stopDiscovery,
} from "../discovery/discovery";
import { requireOnboarded, requireSession } from "../middleware/session";
import { coordinatorNotifier } from "../notifications/notification";

const identifier = z.uuid().transform((value) => value.toLowerCase());
const startRequest = z.strictObject({});
const leaseRequest = z.strictObject({ sessionId: identifier });
const observeRequest = z.strictObject({
  sessionId: identifier,
  peerToken: identifier,
  observationId: identifier,
});

const errorStatus = {
  rate_limited: 429,
  discovery_inactive: 410,
  invalid_peer_token: 410,
  self_encounter: 400,
  observation_conflict: 409,
} as const;

async function parse<T>(context: Context<AppEnv>, schema: z.ZodType<T>) {
  return schema.safeParse(await context.req.json().catch(() => undefined));
}

function owner(context: Context<AppEnv>) {
  return {
    userId: context.var.user.id,
    authSessionId: context.var.authSession.id,
  };
}

function respond<T>(context: Context<AppEnv>, result: DiscoveryResult<T>) {
  if (result.ok) return context.json(result.value);
  if (result.error === "rate_limited") context.header("Retry-After", "60");
  return context.json({ error: result.error }, errorStatus[result.error]);
}

/**
 * Bluetooth reports from phones. Clients are untrusted: a match shows that two
 * signed-in phones reported each other, not that two people were near.
 */
export const discoveryRoutes = new Hono<AppEnv>()
  .use(requireSession, requireOnboarded)
  .post("/start", async (context) => {
    if (!(await parse(context, startRequest)).success) {
      return context.json({ error: "invalid_request" }, 400);
    }
    return respond(
      context,
      await startDiscovery(
        createDatabase(context.env),
        { ...owner(context), authExpiresAt: context.var.authSession.expiresAt },
        new Date(),
      ),
    );
  })
  .post("/rotate", async (context) => {
    const request = await parse(context, leaseRequest);
    if (!request.success)
      return context.json({ error: "invalid_request" }, 400);
    return respond(
      context,
      await rotateDiscovery(
        createDatabase(context.env),
        owner(context),
        request.data.sessionId,
        new Date(),
      ),
    );
  })
  .post("/stop", async (context) => {
    const request = await parse(context, leaseRequest);
    if (!request.success)
      return context.json({ error: "invalid_request" }, 400);
    await stopDiscovery(
      createDatabase(context.env),
      owner(context),
      request.data.sessionId,
    );
    return context.json({ stopped: true });
  })
  .post("/observe", async (context) => {
    const request = await parse(context, observeRequest);
    if (!request.success)
      return context.json({ error: "invalid_request" }, 400);
    return respond(
      context,
      await observePeer(
        createDatabase(context.env),
        coordinatorNotifier(context.env),
        owner(context),
        request.data,
        new Date(),
      ),
    );
  });
