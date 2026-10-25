import type { Database } from "../db/client";
import type {
  ConnectionDecision,
  ConnectionSide,
  ConnectionStatus,
} from "../db/schema";
import type {
  NotificationEvent,
  Notifier,
} from "../notifications/notification";
import {
  agreeToPublic,
  block,
  type Connection,
  decide,
  expire,
  isPastExpiry,
  type TransitionError,
  type TransitionResult,
} from "./lifecycle";
import { otherSide, sideOf, userOnSide } from "./pair";
import {
  expireStaleChancesFor,
  findConnectionFor,
  insertBlock,
  listConnectionsFor,
  loadPublicProfiles,
  updateConnectionIfUnchanged,
} from "./store";
import { type ConnectionView, isVisibleTo, viewConnection } from "./view";

const maxUpdateAttempts = 3;

export type ConnectionActionError = TransitionError | "not_found" | "conflict";

export type ConnectionActionResult =
  | { ok: true; connection: ConnectionView }
  | { ok: false; error: ConnectionActionError };

type ChangeResult =
  | {
      ok: true;
      row: Connection;
      side: ConnectionSide;
      previousStatus: ConnectionStatus;
    }
  | { ok: false; error: ConnectionActionError };

type ConnectionAction = (
  row: Connection,
  side: ConnectionSide,
) => TransitionResult;

/** Lists the person's current connections. Expired chances are left out. */
export async function listConnectionViews(
  db: Database,
  userId: string,
  now: Date,
): Promise<ConnectionView[]> {
  await expireStaleChancesFor(db, userId, now);
  const rows = await listConnectionsFor(db, userId);
  const profiles = await loadPublicProfiles(
    db,
    publicCounterparts(rows, userId),
    now,
  );
  return rows
    .filter((row) => row.status !== "expired")
    .map((row) => viewConnection(row, userId, profiles))
    .filter((view) => view !== null);
}

export async function decideConnection(
  db: Database,
  notifier: Notifier,
  userId: string,
  connectionId: string,
  decision: ConnectionDecision,
  now: Date,
): Promise<ConnectionActionResult> {
  const result = await changeConnection(
    db,
    userId,
    connectionId,
    now,
    (row, side) => decide(row, side, decision, now),
  );
  return finishChange(db, notifier, userId, result, now);
}

export async function goPublic(
  db: Database,
  notifier: Notifier,
  userId: string,
  connectionId: string,
  now: Date,
): Promise<ConnectionActionResult> {
  const result = await changeConnection(
    db,
    userId,
    connectionId,
    now,
    (row, side) => agreeToPublic(row, side, now),
  );
  return finishChange(db, notifier, userId, result, now);
}

/** Blocks the other person on this connection. They are never told. */
export async function blockConnection(
  db: Database,
  notifier: Notifier,
  userId: string,
  connectionId: string,
  now: Date,
): Promise<ConnectionActionResult> {
  const result = await changeConnection(
    db,
    userId,
    connectionId,
    now,
    (row, side) => block(row, side, now),
  );
  if (result.ok) {
    await insertBlock(db, {
      blockerId: userId,
      blockedId: userOnSide(result.row, otherSide(result.side)),
      connectionId: result.row.id,
      createdAt: now,
    });
  }
  return finishChange(db, notifier, userId, result, now);
}

/**
 * Loads the row, applies the action, and saves it only if nobody changed the
 * row in between. Retries from a fresh read when someone did.
 */
async function changeConnection(
  db: Database,
  userId: string,
  connectionId: string,
  now: Date,
  action: ConnectionAction,
): Promise<ChangeResult> {
  for (let attempt = 0; attempt < maxUpdateAttempts; attempt++) {
    const row = await loadCurrentConnection(db, connectionId, userId, now);
    const side = row && sideOf(row, userId);
    if (!row || !side || !isVisibleTo(row, side)) {
      return { ok: false, error: "not_found" };
    }
    const transition = action(row, side);
    if (!transition.ok) return transition;
    if (Object.keys(transition.changes).length === 0) {
      return { ok: true, row, side, previousStatus: row.status };
    }
    const updated = await updateConnectionIfUnchanged(
      db,
      row,
      transition.changes,
    );
    if (updated) {
      return { ok: true, row: updated, side, previousStatus: row.status };
    }
  }
  return { ok: false, error: "conflict" };
}

async function finishChange(
  db: Database,
  notifier: Notifier,
  userId: string,
  result: ChangeResult,
  now: Date,
): Promise<ConnectionActionResult> {
  if (!result.ok) return result;
  if (result.previousStatus !== result.row.status) {
    await announceStatus(notifier, result.row);
  }
  return { ok: true, connection: await viewFor(db, result.row, userId, now) };
}

async function loadCurrentConnection(
  db: Database,
  connectionId: string,
  userId: string,
  now: Date,
): Promise<Connection | null> {
  const row = await findConnectionFor(db, connectionId, userId);
  if (!row || !isPastExpiry(row, now)) return row ?? null;
  return (await updateConnectionIfUnchanged(db, row, expire(row))) ?? row;
}

async function announceStatus(notifier: Notifier, row: Connection) {
  const event = statusEvent(row);
  if (!event) return;
  await Promise.all([
    notifier.send(row.userLowId, event),
    notifier.send(row.userHighId, event),
  ]);
}

function statusEvent(row: Connection): NotificationEvent | null {
  if (row.status === "private") {
    return { kind: "connected", connectionId: row.id };
  }
  if (row.status === "public") return { kind: "public", connectionId: row.id };
  return null;
}

async function viewFor(
  db: Database,
  row: Connection,
  userId: string,
  now: Date,
): Promise<ConnectionView> {
  const profiles = await loadPublicProfiles(
    db,
    publicCounterparts([row], userId),
    now,
  );
  const view = viewConnection(row, userId, profiles);
  if (!view) throw new Error("A participant lost access to their connection");
  return view;
}

export function publicCounterparts(
  rows: Connection[],
  userId: string,
): string[] {
  return rows.flatMap((row) => {
    const side = sideOf(row, userId);
    if (row.status !== "public" || !side) return [];
    return [userOnSide(row, otherSide(side))];
  });
}
