import { hashPassword } from "better-auth/crypto";
import { eq } from "drizzle-orm";
import type { Database } from "../db/client";
import { account, profile, user } from "../db/schema";
import { replaceUserInterests } from "../interests/interest-store";

export const seedPassword = "face2face-seed-password";
export const seedEmailDomain = "seed.face2face.test";

interface SeedUser {
  id: string;
  name: string;
  birthDate: string;
  genderId: string;
  interestIds: string[];
}

/** Overlapping interests, so every pair shares a different set. */
const seedUsers: SeedUser[] = [
  {
    id: "seed-ava",
    name: "Ava",
    birthDate: "1996-03-14",
    genderId: "female",
    interestIds: ["climbing", "coffee", "film", "hiking", "photography"],
  },
  {
    id: "seed-ben",
    name: "Ben",
    birthDate: "1993-11-02",
    genderId: "male",
    interestIds: ["board-games", "coffee", "cooking", "hiking", "video-games"],
  },
  {
    id: "seed-cleo",
    name: "Cleo",
    birthDate: "1999-07-21",
    genderId: "female",
    interestIds: ["jazz", "live-music", "photography", "reading", "travel"],
  },
  {
    id: "seed-dev",
    name: "Dev",
    birthDate: "1990-01-30",
    genderId: "other",
    interestIds: ["cycling", "film", "running", "travel", "yoga"],
  },
  {
    id: "seed-eli",
    name: "Eli",
    birthDate: "2001-09-09",
    genderId: "male",
    interestIds: ["board-games", "film", "jazz", "reading", "video-games"],
  },
  {
    id: "seed-noor",
    name: "Noor",
    birthDate: "1995-05-05",
    genderId: "female",
    interestIds: [],
  },
];

function seedEmail(seed: { id: string }) {
  return `${seed.id.replace(/^seed-/, "")}@${seedEmailDomain}`;
}

/**
 * Creates the seeded people with verified emails, finished onboarding, and
 * the password `seedPassword`. Running it again resets their profiles and
 * interests.
 */
export async function createSeedUsers(db: Database, now: Date) {
  const passwordHash = await hashPassword(seedPassword);
  for (const seed of seedUsers) {
    await upsertSeedUser(db, seed, passwordHash, now);
    await replaceUserInterests(db, seed.id, seed.interestIds, now);
  }
  return seedUsers.map((seed) => seed.id);
}

async function upsertSeedUser(
  db: Database,
  seed: SeedUser,
  passwordHash: string,
  now: Date,
) {
  const existing = await db
    .select({ id: user.id })
    .from(user)
    .where(eq(user.id, seed.id))
    .get();
  const profileValues = {
    userId: seed.id,
    birthDate: seed.birthDate,
    genderId: seed.genderId,
    genderDescription: seed.genderId === "other" ? "Non-binary" : null,
    photoId: null,
    createdAt: now,
    updatedAt: now,
  };
  const profileUpsert = db
    .insert(profile)
    .values(profileValues)
    .onConflictDoUpdate({ target: profile.userId, set: profileValues });
  if (existing) {
    await db.batch([
      db
        .update(user)
        .set({ name: seed.name, updatedAt: now })
        .where(eq(user.id, seed.id)),
      profileUpsert,
    ]);
    return;
  }
  await db.batch([
    db.insert(user).values({
      id: seed.id,
      name: seed.name,
      email: seedEmail(seed),
      emailVerified: true,
      createdAt: now,
      updatedAt: now,
    }),
    db.insert(account).values({
      id: `${seed.id}-credential`,
      accountId: seed.id,
      providerId: "credential",
      userId: seed.id,
      password: passwordHash,
      createdAt: now,
      updatedAt: now,
    }),
    profileUpsert,
  ]);
}
