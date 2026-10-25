import { and, desc, eq, inArray, lte, or, sql } from "drizzle-orm";
import { alias } from "drizzle-orm/sqlite-core";
import type { Database } from "../db/client";
import {
  block,
  connection,
  interest,
  profile,
  profileInterest,
  user,
} from "../db/schema";
import { listInterestNamesByUser } from "../interests/interest-store";
import type { PersonViewer } from "../profiles/person";
import type { Connection, ConnectionChanges } from "./lifecycle";
import type { OrderedPair } from "./pair";
import { ageOn, type PublicProfile } from "./view";

const activeStatuses = ["pending", "private", "public"] as const;

function involves(userId: string) {
  return or(
    eq(connection.userLowId, userId),
    eq(connection.userHighId, userId),
  );
}

function isPair(pair: OrderedPair) {
  return and(
    eq(connection.userLowId, pair.lowId),
    eq(connection.userHighId, pair.highId),
  );
}

function stalePending(now: Date) {
  return and(eq(connection.status, "pending"), lte(connection.expiresAt, now));
}

const expiredAtDeadline = {
  status: "expired" as const,
  resolvedAt: sql`${connection.expiresAt}`,
};

/** Marks every pending chance involving the person that has run out of time. */
export async function expireStaleChancesFor(
  db: Database,
  userId: string,
  now: Date,
) {
  await db
    .update(connection)
    .set(expiredAtDeadline)
    .where(and(stalePending(now), involves(userId)));
}

export async function expireStaleChanceForPair(
  db: Database,
  pair: OrderedPair,
  now: Date,
) {
  await db
    .update(connection)
    .set(expiredAtDeadline)
    .where(and(stalePending(now), isPair(pair)));
}

export async function hasBlockBetween(
  db: Database,
  firstId: string,
  secondId: string,
): Promise<boolean> {
  const found = await db
    .select({ blockerId: block.blockerId })
    .from(block)
    .where(
      or(
        and(eq(block.blockerId, firstId), eq(block.blockedId, secondId)),
        and(eq(block.blockerId, secondId), eq(block.blockedId, firstId)),
      ),
    )
    .get();
  return found !== undefined;
}

export function findActiveConnectionForPair(db: Database, pair: OrderedPair) {
  return db
    .select()
    .from(connection)
    .where(and(isPair(pair), inArray(connection.status, activeStatuses)))
    .get();
}

/** Returns null when the pair already has a pending chance. */
export async function insertChance(
  db: Database,
  row: typeof connection.$inferInsert,
): Promise<Connection | null> {
  const [inserted] = await db
    .insert(connection)
    .values(row)
    .onConflictDoNothing()
    .returning();
  return inserted ?? null;
}

export async function listSharedInterestNames(
  db: Database,
  firstId: string,
  secondId: string,
): Promise<string[]> {
  const other = alias(profileInterest, "other_interest");
  const rows = await db
    .select({ name: interest.name })
    .from(profileInterest)
    .innerJoin(
      other,
      and(
        eq(other.interestId, profileInterest.interestId),
        eq(other.userId, secondId),
      ),
    )
    .innerJoin(interest, eq(interest.id, profileInterest.interestId))
    .where(eq(profileInterest.userId, firstId))
    .orderBy(interest.name);
  return rows.map((row) => row.name);
}

export function listConnectionsFor(db: Database, userId: string) {
  return db
    .select()
    .from(connection)
    .where(involves(userId))
    .orderBy(desc(connection.createdAt));
}

export function findConnectionFor(db: Database, id: string, userId: string) {
  return db
    .select()
    .from(connection)
    .where(and(eq(connection.id, id), involves(userId)))
    .get();
}

/**
 * Applies changes only if the row still has the state they were computed
 * from, so two people answering at once cannot overwrite each other.
 */
export async function updateConnectionIfUnchanged(
  db: Database,
  row: Connection,
  changes: ConnectionChanges,
): Promise<Connection | null> {
  const [updated] = await db
    .update(connection)
    .set(changes)
    .where(
      and(
        eq(connection.id, row.id),
        eq(connection.status, row.status),
        sql`${connection.lowDecision} IS ${row.lowDecision}`,
        sql`${connection.highDecision} IS ${row.highDecision}`,
        sql`${connection.lowPublicAt} IS ${row.lowPublicAt?.getTime() ?? null}`,
        sql`${connection.highPublicAt} IS ${row.highPublicAt?.getTime() ?? null}`,
      ),
    )
    .returning();
  return updated ?? null;
}

export async function insertBlock(
  db: Database,
  values: typeof block.$inferInsert,
) {
  await db.insert(block).values(values).onConflictDoNothing();
}

export async function loadPublicProfiles(
  db: Database,
  viewPerson: PersonViewer,
  userIds: string[],
  today: Date,
): Promise<Map<string, PublicProfile>> {
  if (userIds.length === 0) return new Map();
  const [people, interestsByUser] = await Promise.all([
    db
      .select({
        userId: user.id,
        name: user.name,
        photoId: profile.photoId,
        birthDate: profile.birthDate,
      })
      .from(user)
      .leftJoin(profile, eq(profile.userId, user.id))
      .where(inArray(user.id, userIds)),
    listInterestNamesByUser(db, userIds),
  ]);
  const profiles = await Promise.all(
    people.map(async (person) => ({
      ...(await viewPerson(person)),
      age: person.birthDate ? ageOn(person.birthDate, today) : null,
      interests: interestsByUser.get(person.userId) ?? [],
    })),
  );
  return new Map(profiles.map((profile) => [profile.userId, profile]));
}
