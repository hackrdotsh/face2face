import { and, asc, eq, inArray, sql } from "drizzle-orm";
import type { Database } from "../db/client";
import { interest, profileInterest } from "../db/schema";

export function listInterests(db: Database) {
  return db.select().from(interest).orderBy(asc(interest.name));
}

export interface InterestChoice {
  id: string;
  name: string;
  memberCount: number;
  selected: boolean;
}

/** Every interest, marked with whether this person chose it. */
export function listInterestChoices(
  db: Database,
  userId: string,
): Promise<InterestChoice[]> {
  return db
    .select({
      id: interest.id,
      name: interest.name,
      memberCount: interest.memberCount,
      selected: sql<boolean>`${profileInterest.userId} IS NOT NULL`.mapWith(
        Boolean,
      ),
    })
    .from(interest)
    .leftJoin(
      profileInterest,
      and(
        eq(profileInterest.interestId, interest.id),
        eq(profileInterest.userId, userId),
      ),
    )
    .orderBy(asc(interest.name));
}

/**
 * Replaces the person's interests. Database triggers keep
 * `interest.member_count` in step with these rows.
 */
export async function replaceUserInterests(
  db: Database,
  userId: string,
  interestIds: string[],
  now: Date,
) {
  const removeAll = db
    .delete(profileInterest)
    .where(eq(profileInterest.userId, userId));
  if (interestIds.length === 0) {
    await removeAll;
    return;
  }
  await db.batch([
    removeAll,
    db.insert(profileInterest).values(
      interestIds.map((interestId) => ({
        userId,
        interestId,
        createdAt: now,
      })),
    ),
  ]);
}

export async function listInterestNamesByUser(
  db: Database,
  userIds: string[],
): Promise<Map<string, string[]>> {
  if (userIds.length === 0) return new Map();
  const rows = await db
    .select({ userId: profileInterest.userId, name: interest.name })
    .from(profileInterest)
    .innerJoin(interest, eq(interest.id, profileInterest.interestId))
    .where(inArray(profileInterest.userId, userIds))
    .orderBy(asc(interest.name));
  const namesByUser = new Map<string, string[]>();
  for (const row of rows) {
    namesByUser.set(row.userId, [
      ...(namesByUser.get(row.userId) ?? []),
      row.name,
    ]);
  }
  return namesByUser;
}
