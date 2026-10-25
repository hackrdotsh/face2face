import { and, asc, eq, inArray } from "drizzle-orm";
import type { Database } from "../db/client";
import { block, connection, post, user } from "../db/schema";
import { listInterestNamesByUser } from "../interests/interest-store";
import { seedEmailDomain } from "./seed-users";

export interface DevUser {
  id: string;
  name: string;
  email: string;
  seeded: boolean;
  interests: string[];
}

export async function listDevUsers(db: Database): Promise<DevUser[]> {
  const people = await db
    .select({ id: user.id, name: user.name, email: user.email })
    .from(user)
    .orderBy(asc(user.name));
  const interestsByUser = await listInterestNamesByUser(
    db,
    people.map((person) => person.id),
  );
  return people.map((person) => ({
    ...person,
    seeded: person.email.endsWith(`@${seedEmailDomain}`),
    interests: interestsByUser.get(person.id) ?? [],
  }));
}

export async function usersExist(
  db: Database,
  userIds: string[],
): Promise<boolean> {
  const found = await db
    .select({ id: user.id })
    .from(user)
    .where(inArray(user.id, userIds));
  return found.length === new Set(userIds).size;
}

/** Every connection row with its low and high sides, oldest first. */
export function listAllConnections(db: Database) {
  return db.select().from(connection).orderBy(asc(connection.createdAt));
}

/** Moves a pending chance's deadline to now. The next read marks it expired. */
export async function endChanceNow(db: Database, connectionId: string) {
  const [updated] = await db
    .update(connection)
    .set({ expiresAt: new Date() })
    .where(
      and(eq(connection.id, connectionId), eq(connection.status, "pending")),
    )
    .returning();
  return updated ?? null;
}

export async function deleteAllPosts(db: Database) {
  await db.delete(post);
}

export async function deleteAllConnections(db: Database) {
  await db.batch([db.delete(block), db.delete(connection)]);
}
