import { and, asc, count, eq, gte, inArray, sql } from "drizzle-orm";
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

export const interestNameLength = { min: 2, max: 32 };

/**
 * Trims, collapses spaces, lowercases, and straightens apostrophes so
 * "Board  Games" and "board games" name the same interest.
 */
export function normalizeInterestName(raw: string) {
  return raw
    .normalize("NFC")
    .replace(/[‘’]/g, "'")
    .replace(/\s+/g, " ")
    .trim()
    .toLowerCase();
}

const interestNamePattern = /^[\p{L}\p{N}](?:[\p{L}\p{N} &'-]*[\p{L}\p{N}])?$/u;

/** Why a normalized name can't be used, or undefined when it can. */
export function interestNameProblem(name: string) {
  const length = [...name].length;
  if (length < interestNameLength.min || length > interestNameLength.max) {
    return `Use ${interestNameLength.min} to ${interestNameLength.max} characters.`;
  }
  if (!interestNamePattern.test(name)) {
    return "Use letters, numbers, spaces, &, ', or -.";
  }
  return undefined;
}

export function findInterestByName(db: Database, name: string) {
  return db
    .select({ id: interest.id })
    .from(interest)
    .where(eq(interest.name, name))
    .get();
}

export async function countInterestsCreatedSince(
  db: Database,
  userId: string,
  since: Date,
) {
  const row = await db
    .select({ count: count() })
    .from(interest)
    .where(and(eq(interest.createdBy, userId), gte(interest.createdAt, since)))
    .get();
  return row?.count ?? 0;
}

export async function countUserInterests(db: Database, userId: string) {
  const row = await db
    .select({ count: count() })
    .from(profileInterest)
    .where(eq(profileInterest.userId, userId))
    .get();
  return row?.count ?? 0;
}

/** A readable id from the name, with a random suffix when the slug is taken or empty. */
async function newInterestId(db: Database, name: string) {
  const slug = name
    .normalize("NFKD")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  if (slug) {
    const taken = await db
      .select({ id: interest.id })
      .from(interest)
      .where(eq(interest.id, slug))
      .get();
    if (!taken) return slug;
  }
  const suffix = crypto.randomUUID().slice(0, 8);
  return slug ? `${slug}-${suffix}` : suffix;
}

/**
 * Adds a new interest and selects it for its creator. Returns the id of the
 * interest with this name, which may be one another person created first.
 */
export async function createInterest(
  db: Database,
  userId: string,
  name: string,
  now: Date,
) {
  const id = await newInterestId(db, name);
  await db
    .insert(interest)
    .values({ id, name, createdBy: userId, createdAt: now })
    .onConflictDoNothing({ target: interest.name });
  return (await findInterestByName(db, name))?.id ?? id;
}

export async function addUserInterest(
  db: Database,
  userId: string,
  interestId: string,
  now: Date,
) {
  await db
    .insert(profileInterest)
    .values({ userId, interestId, createdAt: now })
    .onConflictDoNothing();
}
