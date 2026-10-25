import type {
  ConnectionDecision,
  ConnectionSide,
  ConnectionStatus,
} from "../db/schema";
import type { Person } from "../profiles/person";
import {
  type Connection,
  decidedAtOf,
  decisionOf,
  publicAtOf,
} from "./lifecycle";
import { otherSide, sideOf, userOnSide } from "./pair";

export interface PublicProfile extends Person {
  age: number | null;
  interests: string[];
  statusMessage: string | null;
}

/**
 * One connection as a participant sees it. Until both people go public, it
 * shows only the interests they share, the viewer's own choices, and the
 * other person's blob avatar seed. Never their name or photo.
 */
export interface ConnectionView {
  id: string;
  status: ConnectionStatus;
  sharedInterests: string[];
  you: {
    decision: ConnectionDecision | null;
    decidedAt: string | null;
    publicAt: string | null;
  };
  them: PublicProfile | null;
  /** Set while the connection is pending, private, or public. */
  theirAvatar: { seed: string } | null;
  createdAt: string;
  expiresAt: string;
  resolvedAt: string | null;
}

/** What a viewer may know about the other people in their connections. */
export interface Counterparts {
  /** Full profiles, only for public connections. Keyed by user ID. */
  profiles: ReadonlyMap<string, PublicProfile>;
  /** Blob avatar seeds. Keyed by user ID. */
  avatarSeeds: ReadonlyMap<string, string>;
}

const avatarStatuses = new Set<ConnectionStatus>([
  "pending",
  "private",
  "public",
]);

/** A person never sees a connection the other person blocked. */
export function isVisibleTo(row: Connection, side: ConnectionSide): boolean {
  return row.status !== "blocked" || row.blockedBy === side;
}

/** Returns null when the viewer is not a participant or must not see the row. */
export function viewConnection(
  row: Connection,
  viewerId: string,
  counterparts: Counterparts,
): ConnectionView | null {
  const side = sideOf(row, viewerId);
  if (!side || !isVisibleTo(row, side)) return null;
  const otherUserId = userOnSide(row, otherSide(side));
  return {
    id: row.id,
    status: row.status,
    sharedInterests: row.sharedInterests,
    you: {
      decision: decisionOf(row, side),
      decidedAt: isoOrNull(decidedAtOf(row, side)),
      publicAt: isoOrNull(publicAtOf(row, side)),
    },
    them:
      row.status === "public"
        ? (counterparts.profiles.get(otherUserId) ?? null)
        : null,
    theirAvatar: avatarStatuses.has(row.status)
      ? seedOf(counterparts, otherUserId)
      : null,
    createdAt: row.createdAt.toISOString(),
    expiresAt: row.expiresAt.toISOString(),
    resolvedAt: isoOrNull(row.resolvedAt),
  };
}

export function ageOn(birthDate: string, today: Date): number {
  const [year = 0, month = 1, day = 1] = birthDate.split("-").map(Number);
  const hadBirthdayThisYear =
    today.getUTCMonth() + 1 > month ||
    (today.getUTCMonth() + 1 === month && today.getUTCDate() >= day);
  return today.getUTCFullYear() - year - (hadBirthdayThisYear ? 0 : 1);
}

function isoOrNull(date: Date | null): string | null {
  return date ? date.toISOString() : null;
}

function seedOf(
  counterparts: Counterparts,
  userId: string,
): { seed: string } | null {
  const seed = counterparts.avatarSeeds.get(userId);
  return seed ? { seed } : null;
}
