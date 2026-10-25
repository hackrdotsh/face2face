import { and, eq } from "drizzle-orm";
import { sha256 } from "../crypto/sha256";
import type { Database } from "../db/client";
import { pushDevice } from "../db/schema";
import type { PushEnvironment } from "./apns";

/**
 * Registers a phone for one account and removes it from whichever account had
 * it before, so alerts never reach a phone after someone else signs in on it.
 */
export async function claimPushDevice(
  env: Env,
  db: Database,
  userId: string,
  token: string,
  environment: PushEnvironment,
  now: Date,
) {
  const tokenHash = await sha256(token);
  const previous = await db
    .select({ userId: pushDevice.userId })
    .from(pushDevice)
    .where(eq(pushDevice.tokenHash, tokenHash))
    .get();
  if (previous && previous.userId !== userId) {
    await env.USER_COORDINATORS.getByName(previous.userId).unregisterDevice(
      token,
    );
  }
  await db
    .insert(pushDevice)
    .values({ tokenHash, userId, updatedAt: now })
    .onConflictDoUpdate({
      target: pushDevice.tokenHash,
      set: { userId, updatedAt: now },
    });
  await env.USER_COORDINATORS.getByName(userId).registerDevice(
    token,
    environment,
  );
}

export async function releasePushDevice(
  env: Env,
  db: Database,
  userId: string,
  token: string,
) {
  await db
    .delete(pushDevice)
    .where(
      and(
        eq(pushDevice.tokenHash, await sha256(token)),
        eq(pushDevice.userId, userId),
      ),
    );
  await env.USER_COORDINATORS.getByName(userId).unregisterDevice(token);
}
