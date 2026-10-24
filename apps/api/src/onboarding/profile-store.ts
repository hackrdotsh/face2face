import { asc, eq } from "drizzle-orm";
import type { Database } from "../db/client";
import { gender, profile, user } from "../db/schema";
import type { ChoiceOption } from "./field-types";

export interface ProfileSnapshot {
  name: string;
  birthDate: string | null;
  genderId: string | null;
  genderDescription: string | null;
  genderOptions: ChoiceOption[];
}

export interface ProfileChanges {
  user?: { name?: string };
  profile?: {
    birthDate?: string;
    genderId?: string;
    genderDescription?: string | null;
  };
}

export async function loadProfileSnapshot(
  db: Database,
  userId: string,
): Promise<ProfileSnapshot> {
  const [account, genderOptions] = await Promise.all([
    db
      .select({
        name: user.name,
        birthDate: profile.birthDate,
        genderId: profile.genderId,
        genderDescription: profile.genderDescription,
      })
      .from(user)
      .leftJoin(profile, eq(profile.userId, user.id))
      .where(eq(user.id, userId))
      .get(),
    db
      .select({
        id: gender.id,
        label: gender.label,
        allowsDescription: gender.allowsDescription,
      })
      .from(gender)
      .where(eq(gender.active, true))
      .orderBy(asc(gender.sortOrder)),
  ]);
  if (!account) throw new Error("Signed-in user is missing from the database");
  return { ...account, genderOptions };
}

export async function saveProfileChanges(
  db: Database,
  userId: string,
  changes: ProfileChanges,
  now: Date,
) {
  const userUpdate = changes.user
    ? db
        .update(user)
        .set({ ...changes.user, updatedAt: now })
        .where(eq(user.id, userId))
    : undefined;
  const profileUpsert = changes.profile
    ? db
        .insert(profile)
        .values({ userId, ...changes.profile, createdAt: now, updatedAt: now })
        .onConflictDoUpdate({
          target: profile.userId,
          set: { ...changes.profile, updatedAt: now },
        })
    : undefined;
  const statements = [userUpdate, profileUpsert].filter(
    (statement) => statement !== undefined,
  );
  const [first, ...rest] = statements;
  if (first) await db.batch([first, ...rest]);
}

export function mergeProfileChanges(
  changeSets: ProfileChanges[],
): ProfileChanges {
  const merged: ProfileChanges = {};
  for (const changes of changeSets) {
    if (changes.user) merged.user = { ...merged.user, ...changes.user };
    if (changes.profile) {
      merged.profile = { ...merged.profile, ...changes.profile };
    }
  }
  return merged;
}
