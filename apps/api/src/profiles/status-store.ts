import { eq } from "drizzle-orm";
import type { Database } from "../db/client";
import { profile } from "../db/schema";

export const maxStatusMessageLength = 80;

/** One line of text, or null when nothing is left after trimming. */
export function normalizeStatusMessage(text: string): string | null {
  const line = text.replace(/\s+/g, " ").trim();
  return line === "" ? null : line;
}

/** Counts code points, so the limit matches Swift's `unicodeScalars.count`. */
export function isStatusMessageTooLong(text: string): boolean {
  return [...text].length > maxStatusMessageLength;
}

export async function findStatusMessage(
  db: Database,
  userId: string,
): Promise<string | null> {
  const row = await db
    .select({ statusMessage: profile.statusMessage })
    .from(profile)
    .where(eq(profile.userId, userId))
    .get();
  return row?.statusMessage ?? null;
}

export async function saveStatusMessage(
  db: Database,
  userId: string,
  statusMessage: string | null,
  now: Date,
) {
  await db
    .insert(profile)
    .values({ userId, statusMessage, createdAt: now, updatedAt: now })
    .onConflictDoUpdate({
      target: profile.userId,
      set: { statusMessage, updatedAt: now },
    });
}
