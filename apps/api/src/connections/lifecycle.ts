import type {
  ConnectionDecision,
  ConnectionSide,
  connection,
} from "../db/schema";
import { otherSide } from "./pair";

export type Connection = typeof connection.$inferSelect;

export type ConnectionChanges = Partial<
  Pick<
    Connection,
    | "status"
    | "lowDecision"
    | "lowDecidedAt"
    | "highDecision"
    | "highDecidedAt"
    | "lowPublicAt"
    | "highPublicAt"
    | "blockedBy"
    | "resolvedAt"
  >
>;

export type TransitionError =
  | "not_pending"
  | "already_decided"
  | "not_connected"
  | "already_blocked";

export type TransitionResult =
  | { ok: true; changes: ConnectionChanges }
  | { ok: false; error: TransitionError };

export const chanceLifetimeMs = 24 * 60 * 60 * 1000;

export function isPastExpiry(row: Connection, now: Date): boolean {
  return row.status === "pending" && row.expiresAt <= now;
}

export function expire(row: Connection): ConnectionChanges {
  return { status: "expired", resolvedAt: row.expiresAt };
}

/**
 * Records one side's answer. A decline ends the chance as `expired`, so the
 * other person cannot tell it apart from a timeout.
 */
export function decide(
  row: Connection,
  side: ConnectionSide,
  decision: ConnectionDecision,
  now: Date,
): TransitionResult {
  if (row.status !== "pending") return { ok: false, error: "not_pending" };
  if (decisionOf(row, side)) return { ok: false, error: "already_decided" };
  const recorded = decisionChanges(side, decision, now);
  if (decision === "declined") {
    return {
      ok: true,
      changes: { ...recorded, status: "expired", resolvedAt: now },
    };
  }
  if (decisionOf(row, otherSide(side)) === "accepted") {
    return {
      ok: true,
      changes: { ...recorded, status: "private", resolvedAt: now },
    };
  }
  return { ok: true, changes: recorded };
}

/** Records one side's consent to go public. Asking again changes nothing. */
export function agreeToPublic(
  row: Connection,
  side: ConnectionSide,
  now: Date,
): TransitionResult {
  if (row.status !== "private" && row.status !== "public") {
    return { ok: false, error: "not_connected" };
  }
  if (publicAtOf(row, side)) return { ok: true, changes: {} };
  const recorded = publicAtChanges(side, now);
  if (publicAtOf(row, otherSide(side))) {
    return { ok: true, changes: { ...recorded, status: "public" } };
  }
  return { ok: true, changes: recorded };
}

export function block(
  row: Connection,
  side: ConnectionSide,
  now: Date,
): TransitionResult {
  if (row.status === "blocked") return { ok: false, error: "already_blocked" };
  return {
    ok: true,
    changes: {
      status: "blocked",
      blockedBy: side,
      resolvedAt: row.resolvedAt ?? now,
    },
  };
}

export function decisionOf(row: Connection, side: ConnectionSide) {
  return side === "low" ? row.lowDecision : row.highDecision;
}

export function decidedAtOf(row: Connection, side: ConnectionSide) {
  return side === "low" ? row.lowDecidedAt : row.highDecidedAt;
}

export function publicAtOf(row: Connection, side: ConnectionSide) {
  return side === "low" ? row.lowPublicAt : row.highPublicAt;
}

function decisionChanges(
  side: ConnectionSide,
  decision: ConnectionDecision,
  now: Date,
): ConnectionChanges {
  return side === "low"
    ? { lowDecision: decision, lowDecidedAt: now }
    : { highDecision: decision, highDecidedAt: now };
}

function publicAtChanges(side: ConnectionSide, now: Date): ConnectionChanges {
  return side === "low" ? { lowPublicAt: now } : { highPublicAt: now };
}
