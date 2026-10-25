import { eq } from "drizzle-orm";
import type { Database } from "../db/client";
import { profile } from "../db/schema";

export async function findPhotoId(
  db: Database,
  userId: string,
): Promise<string | null> {
  const row = await db
    .select({ photoId: profile.photoId })
    .from(profile)
    .where(eq(profile.userId, userId))
    .get();
  return row?.photoId ?? null;
}

/** Returns the photo it replaced, so its files can be deleted. */
export async function savePhotoId(
  db: Database,
  userId: string,
  photoId: string | null,
  now: Date,
): Promise<string | null> {
  const previous = await findPhotoId(db, userId);
  await db
    .insert(profile)
    .values({ userId, photoId, createdAt: now, updatedAt: now })
    .onConflictDoUpdate({
      target: profile.userId,
      set: { photoId, updatedAt: now },
    });
  return previous;
}
