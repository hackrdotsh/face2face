import { recordEncounter } from "../connections/encounter";
import { listSharedInterestNames } from "../connections/store";
import { sha256 } from "../crypto/sha256";
import type { Database } from "../db/client";
import type { Notifier } from "../notifications/notification";
import {
  countQuota,
  type DiscoveryLeaseRow,
  type DiscoveryObservationRow,
  deleteExpiredDiscoveryRows,
  deleteLease,
  findActiveLease,
  findLeaseByToken,
  findObservation,
  hasReciprocalReport,
  insertObservation,
  insertToken,
  type LeaseOwner,
  leasesAlreadyMatched,
  markMatched,
  replaceLease,
} from "./discovery-store";

export const discoveryPolicy = {
  tokenTTL: 5 * 60_000,
  sessionTTL: 30 * 60_000,
  reciprocalWindow: 2 * 60_000,
};

const quotaPerMinute = { start: 10, rotate: 12, observe: 120 } as const;

export interface DiscoveryOwner extends LeaseOwner {
  authExpiresAt: Date;
}

export interface DiscoveryLease {
  sessionId: string;
  token: string;
  expiresAt: number;
  sessionExpiresAt: number;
  serverTime: number;
}

/**
 * A receipt never says who the peer is or whether a block stopped the chance.
 * `matchId` is the same for both phones and stays stable for one pair of leases.
 * A reciprocal pair that shares no interests gets `noSharedInterests` and no chance.
 */
export type ObservationReceipt =
  | { status: "pending" }
  | { status: "recorded" | "noSharedInterests"; matchId: string };

export type DiscoveryError =
  | "rate_limited"
  | "discovery_inactive"
  | "invalid_peer_token"
  | "self_encounter"
  | "observation_conflict";

export type DiscoveryResult<T> =
  | { ok: true; value: T }
  | { ok: false; error: DiscoveryError };

function minuteOf(now: Date) {
  return Math.floor(now.getTime() / 60_000);
}

async function withinQuota(
  db: Database,
  userId: string,
  action: keyof typeof quotaPerMinute,
  now: Date,
) {
  const count = await countQuota(db, userId, action, minuteOf(now));
  return count <= quotaPerMinute[action];
}

function earliest(...dates: Date[]) {
  return new Date(Math.min(...dates.map((date) => date.getTime())));
}

function leaseResponse(
  lease: DiscoveryLeaseRow,
  token: string,
  tokenExpiresAt: Date,
  now: Date,
): DiscoveryLease {
  return {
    sessionId: lease.id,
    token,
    expiresAt: tokenExpiresAt.getTime(),
    sessionExpiresAt: lease.expiresAt.getTime(),
    serverTime: now.getTime(),
  };
}

/** Opts the account in for one lease, ending any lease it already had. */
export async function startDiscovery(
  db: Database,
  owner: DiscoveryOwner,
  now: Date,
): Promise<DiscoveryResult<DiscoveryLease>> {
  if (!(await withinQuota(db, owner.userId, "start", now))) {
    return { ok: false, error: "rate_limited" };
  }
  await deleteExpiredDiscoveryRows(
    db,
    now,
    new Date(now.getTime() - discoveryPolicy.sessionTTL),
  );
  const lease: DiscoveryLeaseRow = {
    id: crypto.randomUUID(),
    userId: owner.userId,
    authSessionId: owner.authSessionId,
    createdAt: now,
    expiresAt: earliest(
      new Date(now.getTime() + discoveryPolicy.sessionTTL),
      owner.authExpiresAt,
    ),
  };
  const token = crypto.randomUUID();
  const tokenExpiresAt = earliest(
    new Date(now.getTime() + discoveryPolicy.tokenTTL),
    lease.expiresAt,
  );
  await replaceLease(db, lease, await sha256(token), tokenExpiresAt);
  return { ok: true, value: leaseResponse(lease, token, tokenExpiresAt, now) };
}

/** Adds a token. Older tokens stay valid until they expire, so handshakes in flight can finish. */
export async function rotateDiscovery(
  db: Database,
  owner: LeaseOwner,
  sessionId: string,
  now: Date,
): Promise<DiscoveryResult<DiscoveryLease>> {
  const lease = await findActiveLease(db, owner, sessionId, now);
  if (!lease) return { ok: false, error: "discovery_inactive" };
  if (!(await withinQuota(db, owner.userId, "rotate", now))) {
    return { ok: false, error: "rate_limited" };
  }
  const token = crypto.randomUUID();
  const expiresAt = earliest(
    new Date(now.getTime() + discoveryPolicy.tokenTTL),
    lease.expiresAt,
  );
  await insertToken(db, lease.id, await sha256(token), expiresAt);
  return { ok: true, value: leaseResponse(lease, token, expiresAt, now) };
}

/** Idempotent, and does not reveal whether someone else's lease exists. */
export async function stopDiscovery(
  db: Database,
  owner: LeaseOwner,
  sessionId: string,
) {
  await deleteLease(db, owner, sessionId);
}

export interface Observation {
  sessionId: string;
  peerToken: string;
  /** Chosen by the phone and reused on retries. */
  observationId: string;
}

/**
 * Records that this lease heard a peer's token. When the peer's lease heard this
 * one within the reciprocal window and the two people share an interest, both
 * of them get an encounter.
 */
export async function observePeer(
  db: Database,
  notifier: Notifier,
  owner: LeaseOwner,
  observation: Observation,
  now: Date,
): Promise<DiscoveryResult<ObservationReceipt>> {
  const own = await findActiveLease(db, owner, observation.sessionId, now);
  if (!own) return { ok: false, error: "discovery_inactive" };
  const tokenHash = await sha256(observation.peerToken);
  const id = await sha256(`${own.id}:${observation.observationId}`);

  const previous = await findObservation(db, id, own.id);
  if (previous) return receiptFor(db, owner.userId, previous, tokenHash);

  if (!(await withinQuota(db, owner.userId, "observe", now))) {
    return { ok: false, error: "rate_limited" };
  }
  const peer = await findLeaseByToken(db, tokenHash, now);
  if (!peer) return { ok: false, error: "invalid_peer_token" };
  if (peer.userId === owner.userId) {
    return { ok: false, error: "self_encounter" };
  }

  await insertObservation(db, {
    id,
    observerSessionId: own.id,
    peerSessionId: peer.id,
    peerUserId: peer.userId,
    peerTokenHash: tokenHash,
    receivedAt: now,
    matchedAt: null,
  });
  const since = new Date(now.getTime() - discoveryPolicy.reciprocalWindow);
  if (await hasReciprocalReport(db, own.id, peer.id, since)) {
    // One encounter per pair of leases, so a decline is not undone on the same walk.
    const matchedBefore = await leasesAlreadyMatched(db, own.id, peer.id);
    await markMatched(db, own.id, peer.id, now);
    if (
      !matchedBefore &&
      (await sharesInterest(db, owner.userId, peer.userId))
    ) {
      await recordEncounter(db, notifier, owner.userId, peer.userId, now);
    }
  }

  const accepted = await findObservation(db, id, own.id);
  if (!accepted) return { ok: false, error: "discovery_inactive" };
  return receiptFor(db, owner.userId, accepted, tokenHash);
}

async function sharesInterest(db: Database, userId: string, peerId: string) {
  return (await listSharedInterestNames(db, userId, peerId)).length > 0;
}

async function receiptFor(
  db: Database,
  userId: string,
  row: DiscoveryObservationRow,
  tokenHash: string,
): Promise<DiscoveryResult<ObservationReceipt>> {
  if (row.peerTokenHash !== tokenHash) {
    return { ok: false, error: "observation_conflict" };
  }
  if (!row.matchedAt) return { ok: true, value: { status: "pending" } };
  const leases = [row.observerSessionId, row.peerSessionId].sort();
  const matchId = await sha256(leases.join(":"));
  const status = (await sharesInterest(db, userId, row.peerUserId))
    ? "recorded"
    : "noSharedInterests";
  return { ok: true, value: { status, matchId } };
}
