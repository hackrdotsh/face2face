import type { Database } from "../db/client";
import type { Notifier } from "../notifications/notification";
import { type Connection, chanceLifetimeMs } from "./lifecycle";
import { orderPair } from "./pair";
import {
  expireStaleChanceForPair,
  findActiveConnectionForPair,
  hasBlockBetween,
  insertChance,
  listSharedInterestNames,
} from "./store";

export type EncounterOutcome =
  | { kind: "created"; connection: Connection }
  /** The pair already has a pending, private, or public connection. */
  | { kind: "alreadyActive"; connection: Connection }
  /** One person blocked the other. The reporter is not told which. */
  | { kind: "ignored" };

/**
 * Opens a 24-hour chance for two people who passed each other and tells both
 * of them which interests they share.
 */
export async function recordEncounter(
  db: Database,
  notifier: Notifier,
  firstUserId: string,
  secondUserId: string,
  now: Date,
): Promise<EncounterOutcome> {
  if (await hasBlockBetween(db, firstUserId, secondUserId)) {
    return { kind: "ignored" };
  }
  const pair = orderPair(firstUserId, secondUserId);
  await expireStaleChanceForPair(db, pair, now);
  const active = await findActiveConnectionForPair(db, pair);
  if (active) return { kind: "alreadyActive", connection: active };

  const inserted = await insertChance(db, {
    id: crypto.randomUUID(),
    userLowId: pair.lowId,
    userHighId: pair.highId,
    status: "pending",
    sharedInterests: await listSharedInterestNames(db, pair.lowId, pair.highId),
    createdAt: now,
    expiresAt: new Date(now.getTime() + chanceLifetimeMs),
  });
  if (!inserted) {
    const raced = await findActiveConnectionForPair(db, pair);
    if (raced) return { kind: "alreadyActive", connection: raced };
    throw new Error("A pending chance conflicted but could not be found");
  }

  await notifyBoth(notifier, inserted);
  return { kind: "created", connection: inserted };
}

async function notifyBoth(notifier: Notifier, row: Connection) {
  const event = {
    kind: "encounter",
    connectionId: row.id,
    sharedInterests: row.sharedInterests,
    expiresAt: row.expiresAt.toISOString(),
  } as const;
  await Promise.all([
    notifier.send(row.userLowId, event),
    notifier.send(row.userHighId, event),
  ]);
}
