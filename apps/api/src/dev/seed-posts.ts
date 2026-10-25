import { like } from "drizzle-orm";
import type { Database } from "../db/client";
import { post, postAttendee } from "../db/schema";

const hourMs = 60 * 60 * 1000;
const dayMs = 24 * hourMs;

interface SeedPost {
  id: string;
  forumId: string;
  authorId: string;
  title: string;
  description?: string;
  location?: string;
  /** Hours from the time of seeding. */
  startsIn: number;
  lastsHours?: number;
  cancelled?: boolean;
  attendeeIds: string[];
}

/**
 * Each author and attendee has the forum's interest in `seed-users.ts`.
 * Includes an event in progress, one that is over, and one that is cancelled.
 */
const seedPosts: SeedPost[] = [
  {
    id: "seed-post-catan",
    forumId: "board-games",
    authorId: "seed-eli",
    title: "Catan and pizza night",
    description: "Bring a game if you have one. Pizza is on me.",
    location: "Eli's place, buzz 304",
    startsIn: 1 * 24 + 6,
    lastsHours: 4,
    attendeeIds: ["seed-ben"],
  },
  {
    id: "seed-post-latte-art",
    forumId: "coffee",
    authorId: "seed-ava",
    title: "Latte art throwdown",
    description: "Friendly competition. Winner picks the next café.",
    location: "Corner café on 4th Street",
    startsIn: 2 * 24,
    lastsHours: 2,
    attendeeIds: ["seed-ben", "seed-ava"],
  },
  {
    id: "seed-post-5k",
    forumId: "running",
    authorId: "seed-dev",
    title: "Saturday 5K along the river",
    description: "Easy pace, no one gets left behind.",
    location: "River path, east footbridge",
    startsIn: 2 * 24 + 20,
    attendeeIds: [],
  },
  {
    id: "seed-post-kubrick",
    forumId: "film",
    authorId: "seed-dev",
    title: "Kubrick double feature",
    description: "2001, then The Shining. Snacks welcome.",
    location: "Community hall screening room",
    startsIn: 3 * 24 + 8,
    lastsHours: 5,
    attendeeIds: ["seed-ava", "seed-eli", "seed-dev"],
  },
  {
    id: "seed-post-jam",
    forumId: "jazz",
    authorId: "seed-cleo",
    title: "Open jam night",
    location: "Basement bar on 9th Avenue",
    startsIn: 4 * 24 + 9,
    lastsHours: 3,
    attendeeIds: ["seed-eli"],
  },
  {
    id: "seed-post-sunrise-hike",
    forumId: "hiking",
    authorId: "seed-ben",
    title: "Sunrise hike",
    description: "Leaving the trailhead at 6. Headlamps recommended.",
    location: "North trailhead parking lot",
    startsIn: 5 * 24 - 6,
    lastsHours: 5,
    attendeeIds: ["seed-ava"],
  },
  {
    id: "seed-post-photo-walk",
    forumId: "photography",
    authorId: "seed-cleo",
    title: "Golden hour photo walk",
    location: "Old town fountain",
    startsIn: 6 * 24 + 7,
    lastsHours: 2,
    attendeeIds: ["seed-ava", "seed-cleo"],
  },
  {
    id: "seed-post-book-club",
    forumId: "reading",
    authorId: "seed-eli",
    title: "Book club: Piranesi",
    description: "We'll discuss the whole book. Spoilers ahead.",
    location: "Library, second floor study room",
    startsIn: 9 * 24 + 8,
    lastsHours: 2,
    attendeeIds: ["seed-cleo"],
  },
  {
    id: "seed-post-trip-planning",
    forumId: "travel",
    authorId: "seed-dev",
    title: "Mountain weekend trip planning",
    description: "Splitting a cabin. Come with dates that work for you.",
    startsIn: 12 * 24 + 2,
    attendeeIds: ["seed-cleo"],
  },
  {
    id: "seed-post-bouldering",
    forumId: "climbing",
    authorId: "seed-ava",
    title: "Drop-in bouldering",
    description: "Already here. Come find me by the cave wall.",
    location: "Downtown climbing gym",
    startsIn: -1,
    lastsHours: 3,
    attendeeIds: ["seed-ava"],
  },
  {
    id: "seed-post-cupping",
    forumId: "coffee",
    authorId: "seed-ben",
    title: "Cupping session",
    location: "Roastery on Industrial Way",
    startsIn: -3 * 24,
    lastsHours: 2,
    attendeeIds: ["seed-ava"],
  },
  {
    id: "seed-post-tournament",
    forumId: "video-games",
    authorId: "seed-ben",
    title: "Fighting game tournament",
    location: "Ben's place",
    startsIn: 7 * 24 + 6,
    cancelled: true,
    attendeeIds: ["seed-eli"],
  },
];

/**
 * Replaces the seeded forum posts and their RSVPs. Times are relative to
 * `now`. The seeded people must exist first.
 */
export async function createSeedPosts(db: Database, now: Date) {
  const nowMs = now.getTime();
  const createdAt = new Date(nowMs - 2 * dayMs);
  const posts = seedPosts.map((seed, index) => {
    const startsAt = new Date(nowMs + seed.startsIn * hourMs);
    // Spreads creation times so the newest-first feed has a stable order.
    const postedAt = new Date(createdAt.getTime() + index * hourMs);
    return {
      id: seed.id,
      forumId: seed.forumId,
      authorId: seed.authorId,
      title: seed.title,
      description: seed.description ?? null,
      location: seed.location ?? null,
      startsAt,
      endsAt: seed.lastsHours
        ? new Date(startsAt.getTime() + seed.lastsHours * hourMs)
        : null,
      createdAt: postedAt,
      updatedAt: postedAt,
      deletedAt: seed.cancelled ? postedAt : null,
    };
  });
  const attendees = seedPosts.flatMap((seed) =>
    seed.attendeeIds.map((userId) => ({
      postId: seed.id,
      userId,
      createdAt: now,
    })),
  );
  // One row per statement keeps each under D1's limit on bound parameters.
  await db.batch([
    db.delete(post).where(like(post.id, "seed-post-%")),
    ...posts.map((row) => db.insert(post).values(row)),
    ...attendees.map((row) => db.insert(postAttendee).values(row)),
  ]);
  return seedPosts.map((seed) => seed.id);
}
