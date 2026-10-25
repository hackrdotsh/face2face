import {
  and,
  eq,
  gt,
  gte,
  inArray,
  isNotNull,
  isNull,
  lt,
  or,
  sql,
} from "drizzle-orm";
import type { Database } from "../db/client";
import {
  discoveryObservation,
  discoveryQuota,
  discoverySession,
  discoveryToken,
} from "../db/schema";

export type DiscoveryLeaseRow = typeof discoverySession.$inferSelect;
export type DiscoveryObservationRow = typeof discoveryObservation.$inferSelect;

export interface LeaseOwner {
  userId: string;
  authSessionId: string;
}

/** Counts one action in the current minute and returns the new total. */
export async function countQuota(
  db: Database,
  userId: string,
  action: string,
  minute: number,
) {
  const [row] = await db
    .insert(discoveryQuota)
    .values({ userId, action, minute, count: 1 })
    .onConflictDoUpdate({
      target: [
        discoveryQuota.userId,
        discoveryQuota.action,
        discoveryQuota.minute,
      ],
      set: { count: sql`${discoveryQuota.count} + 1` },
    })
    .returning({ count: discoveryQuota.count });
  return row?.count ?? Number.POSITIVE_INFINITY;
}

/** Deletes a bounded batch of expired rows. There is no scheduled job. */
export async function deleteExpiredDiscoveryRows(
  db: Database,
  now: Date,
  observationCutoff: Date,
) {
  await db.batch([
    db
      .delete(discoverySession)
      .where(
        inArray(
          discoverySession.id,
          db
            .select({ id: discoverySession.id })
            .from(discoverySession)
            .where(lt(discoverySession.expiresAt, now))
            .limit(20),
        ),
      ),
    db
      .delete(discoveryToken)
      .where(
        inArray(
          discoveryToken.hash,
          db
            .select({ hash: discoveryToken.hash })
            .from(discoveryToken)
            .where(lt(discoveryToken.expiresAt, now))
            .limit(200),
        ),
      ),
    db
      .delete(discoveryObservation)
      .where(
        inArray(
          discoveryObservation.id,
          db
            .select({ id: discoveryObservation.id })
            .from(discoveryObservation)
            .where(lt(discoveryObservation.receivedAt, observationCutoff))
            .limit(200),
        ),
      ),
    db
      .delete(discoveryQuota)
      .where(
        sql`rowid IN (SELECT rowid FROM ${discoveryQuota} WHERE ${discoveryQuota.minute} < ${Math.floor(now.getTime() / 60_000) - 2} LIMIT 100)`,
      ),
  ]);
}

/** Replaces the account's lease, which revokes every token of the old one. */
export async function replaceLease(
  db: Database,
  lease: DiscoveryLeaseRow,
  tokenHash: string,
  tokenExpiresAt: Date,
) {
  await db.batch([
    db
      .delete(discoverySession)
      .where(eq(discoverySession.userId, lease.userId)),
    db.insert(discoverySession).values(lease),
    db.insert(discoveryToken).values({
      hash: tokenHash,
      sessionId: lease.id,
      expiresAt: tokenExpiresAt,
    }),
  ]);
}

export async function insertToken(
  db: Database,
  sessionId: string,
  hash: string,
  expiresAt: Date,
) {
  await db.insert(discoveryToken).values({ hash, sessionId, expiresAt });
}

export async function findActiveLease(
  db: Database,
  owner: LeaseOwner,
  sessionId: string,
  now: Date,
) {
  return db.query.discoverySession.findFirst({
    where: and(
      eq(discoverySession.id, sessionId),
      eq(discoverySession.userId, owner.userId),
      eq(discoverySession.authSessionId, owner.authSessionId),
      gt(discoverySession.expiresAt, now),
    ),
  });
}

export async function deleteLease(
  db: Database,
  owner: LeaseOwner,
  sessionId: string,
) {
  await db
    .delete(discoverySession)
    .where(
      and(
        eq(discoverySession.id, sessionId),
        eq(discoverySession.userId, owner.userId),
        eq(discoverySession.authSessionId, owner.authSessionId),
      ),
    );
}

/** The live lease that owns an unexpired token. */
export async function findLeaseByToken(
  db: Database,
  tokenHash: string,
  now: Date,
) {
  const [row] = await db
    .select({ lease: discoverySession })
    .from(discoveryToken)
    .innerJoin(
      discoverySession,
      eq(discoverySession.id, discoveryToken.sessionId),
    )
    .where(
      and(
        eq(discoveryToken.hash, tokenHash),
        gt(discoveryToken.expiresAt, now),
        gt(discoverySession.expiresAt, now),
      ),
    )
    .limit(1);
  return row?.lease;
}

export async function findObservation(
  db: Database,
  id: string,
  observerSessionId: string,
) {
  return db.query.discoveryObservation.findFirst({
    where: and(
      eq(discoveryObservation.id, id),
      eq(discoveryObservation.observerSessionId, observerSessionId),
    ),
  });
}

export async function insertObservation(
  db: Database,
  row: DiscoveryObservationRow,
) {
  await db.insert(discoveryObservation).values(row).onConflictDoNothing();
}

/** Whether the peer reported this session since `since`. */
export async function hasReciprocalReport(
  db: Database,
  ownSessionId: string,
  peerSessionId: string,
  since: Date,
) {
  const row = await db.query.discoveryObservation.findFirst({
    columns: { id: true },
    where: and(
      eq(discoveryObservation.observerSessionId, peerSessionId),
      eq(discoveryObservation.peerSessionId, ownSessionId),
      gte(discoveryObservation.receivedAt, since),
    ),
  });
  return row !== undefined;
}

/** Whether these two leases already produced an encounter. */
export async function leasesAlreadyMatched(
  db: Database,
  firstSessionId: string,
  secondSessionId: string,
) {
  const row = await db.query.discoveryObservation.findFirst({
    columns: { id: true },
    where: and(
      isNotNull(discoveryObservation.matchedAt),
      or(
        and(
          eq(discoveryObservation.observerSessionId, firstSessionId),
          eq(discoveryObservation.peerSessionId, secondSessionId),
        ),
        and(
          eq(discoveryObservation.observerSessionId, secondSessionId),
          eq(discoveryObservation.peerSessionId, firstSessionId),
        ),
      ),
    ),
  });
  return row !== undefined;
}

/** Marks every unmatched report between two leases as matched. */
export async function markMatched(
  db: Database,
  firstSessionId: string,
  secondSessionId: string,
  now: Date,
) {
  await db
    .update(discoveryObservation)
    .set({ matchedAt: now })
    .where(
      and(
        isNull(discoveryObservation.matchedAt),
        or(
          and(
            eq(discoveryObservation.observerSessionId, firstSessionId),
            eq(discoveryObservation.peerSessionId, secondSessionId),
          ),
          and(
            eq(discoveryObservation.observerSessionId, secondSessionId),
            eq(discoveryObservation.peerSessionId, firstSessionId),
          ),
        ),
      ),
    );
}
