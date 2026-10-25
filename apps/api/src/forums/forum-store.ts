import {
  and,
  asc,
  desc,
  eq,
  gt,
  inArray,
  isNull,
  lt,
  lte,
  or,
  sql,
} from "drizzle-orm";
import type { Database } from "../db/client";
import {
  forum,
  interest,
  post,
  postAttendee,
  profile,
  profileInterest,
  user,
} from "../db/schema";
import type { PersonRow } from "../profiles/person";

export type Post = typeof post.$inferSelect;
export type PostFields = Pick<
  Post,
  "title" | "description" | "location" | "startsAt" | "endsAt"
>;

export interface PostRow {
  post: Post;
  author: PersonRow;
  attending: boolean;
}

export const attendeePreviewSize = 5;

function isMember(userId: string) {
  return and(
    eq(profileInterest.interestId, forum.interestId),
    eq(profileInterest.userId, userId),
  );
}

/** Ends at `ends_at`, or at `starts_at` when there is no end time. */
function isUpcoming(now: Date) {
  return gt(sql`coalesce(${post.endsAt}, ${post.startsAt})`, now.getTime());
}

/** The forums of the person's interests, with their upcoming post counts. */
export function listForumsFor(db: Database, userId: string, now: Date) {
  return db
    .select({
      id: forum.id,
      interestId: interest.id,
      interestName: interest.name,
      upcomingPostCount: sql<number>`count(${post.id})`.mapWith(Number),
    })
    .from(forum)
    .innerJoin(profileInterest, isMember(userId))
    .innerJoin(interest, eq(interest.id, forum.interestId))
    .leftJoin(
      post,
      and(eq(post.forumId, forum.id), isNull(post.deletedAt), isUpcoming(now)),
    )
    .groupBy(forum.id)
    .orderBy(asc(interest.name));
}

export async function findForumFor(
  db: Database,
  forumId: string,
  userId: string,
) {
  return db
    .select({ id: forum.id, interestName: interest.name })
    .from(forum)
    .innerJoin(profileInterest, isMember(userId))
    .innerJoin(interest, eq(interest.id, forum.interestId))
    .where(eq(forum.id, forumId))
    .get();
}

function selectPostRows(db: Database, viewerId: string) {
  return db
    .select({
      post,
      author: { userId: user.id, name: user.name, photoId: profile.photoId },
      attending: sql<boolean>`${postAttendee.userId} IS NOT NULL`.mapWith(
        Boolean,
      ),
    })
    .from(post)
    .innerJoin(user, eq(user.id, post.authorId))
    .leftJoin(profile, eq(profile.userId, user.id))
    .leftJoin(
      postAttendee,
      and(eq(postAttendee.postId, post.id), eq(postAttendee.userId, viewerId)),
    );
}

/** Returns undefined unless the post is in one of the person's forums. */
export async function findPostFor(
  db: Database,
  postId: string,
  userId: string,
): Promise<PostRow | undefined> {
  return selectPostRows(db, userId)
    .innerJoin(forum, eq(forum.id, post.forumId))
    .innerJoin(profileInterest, isMember(userId))
    .where(eq(post.id, postId))
    .get();
}

/**
 * Upcoming posts from every forum the person can see, soonest start first.
 * `after` is the last post ID of the previous page.
 */
export async function listUpcomingPosts(
  db: Database,
  viewerId: string,
  after: string | undefined,
  limit: number,
  now: Date,
): Promise<{ rows: PostRow[]; hasMore: boolean }> {
  const cursor = after
    ? await db
        .select({ id: post.id, startsAt: post.startsAt })
        .from(post)
        .where(eq(post.id, after))
        .get()
    : undefined;
  const rows = await selectPostRows(db, viewerId)
    .innerJoin(forum, eq(forum.id, post.forumId))
    .innerJoin(profileInterest, isMember(viewerId))
    .where(
      and(
        isNull(post.deletedAt),
        isUpcoming(now),
        cursor
          ? or(
              gt(post.startsAt, cursor.startsAt),
              and(eq(post.startsAt, cursor.startsAt), gt(post.id, cursor.id)),
            )
          : undefined,
      ),
    )
    .orderBy(asc(post.startsAt), asc(post.id))
    .limit(limit + 1);
  return { rows: rows.slice(0, limit), hasMore: rows.length > limit };
}

/** Newest first. `before` is the last post ID of the previous page. */
export async function listForumPosts(
  db: Database,
  forumId: string,
  viewerId: string,
  before: string | undefined,
  limit: number,
): Promise<{ rows: PostRow[]; hasMore: boolean }> {
  const cursor = before
    ? await db
        .select({ id: post.id, createdAt: post.createdAt })
        .from(post)
        .where(and(eq(post.id, before), eq(post.forumId, forumId)))
        .get()
    : undefined;
  const rows = await selectPostRows(db, viewerId)
    .where(
      and(
        eq(post.forumId, forumId),
        isNull(post.deletedAt),
        cursor
          ? or(
              lt(post.createdAt, cursor.createdAt),
              and(eq(post.createdAt, cursor.createdAt), lt(post.id, cursor.id)),
            )
          : undefined,
      ),
    )
    .orderBy(desc(post.createdAt), desc(post.id))
    .limit(limit + 1);
  return { rows: rows.slice(0, limit), hasMore: rows.length > limit };
}

/** The first attendees of each post, by RSVP time. */
export async function listAttendeePreviews(
  db: Database,
  postIds: string[],
): Promise<Map<string, PersonRow[]>> {
  const previews = new Map<string, PersonRow[]>();
  if (postIds.length === 0) return previews;
  const ranked = db
    .select({
      postId: postAttendee.postId,
      userId: user.id,
      name: user.name,
      photoId: profile.photoId,
      rank: sql<number>`row_number() OVER (PARTITION BY ${postAttendee.postId} ORDER BY ${postAttendee.createdAt}, ${postAttendee.userId})`.as(
        "rank",
      ),
    })
    .from(postAttendee)
    .innerJoin(user, eq(user.id, postAttendee.userId))
    .leftJoin(profile, eq(profile.userId, user.id))
    .where(inArray(postAttendee.postId, postIds))
    .as("ranked");
  const rows = await db
    .select()
    .from(ranked)
    .where(lte(ranked.rank, attendeePreviewSize))
    .orderBy(asc(ranked.postId), asc(ranked.rank));
  for (const { postId, userId, name, photoId } of rows) {
    const list = previews.get(postId) ?? [];
    list.push({ userId, name, photoId });
    previews.set(postId, list);
  }
  return previews;
}

export function listAttendees(
  db: Database,
  postId: string,
): Promise<PersonRow[]> {
  return db
    .select({ userId: user.id, name: user.name, photoId: profile.photoId })
    .from(postAttendee)
    .innerJoin(user, eq(user.id, postAttendee.userId))
    .leftJoin(profile, eq(profile.userId, user.id))
    .where(eq(postAttendee.postId, postId))
    .orderBy(asc(postAttendee.createdAt), asc(postAttendee.userId));
}

export async function listAttendeeIds(
  db: Database,
  postId: string,
): Promise<string[]> {
  const rows = await db
    .select({ userId: postAttendee.userId })
    .from(postAttendee)
    .where(eq(postAttendee.postId, postId));
  return rows.map((row) => row.userId);
}

export async function insertPost(
  db: Database,
  values: PostFields & { forumId: string; authorId: string },
  now: Date,
): Promise<string> {
  const id = crypto.randomUUID();
  await db
    .insert(post)
    .values({ ...values, id, createdAt: now, updatedAt: now });
  return id;
}

/** Changes a post only while it is the author's and not deleted. */
export async function updateLivePost(
  db: Database,
  postId: string,
  authorId: string,
  changes: Partial<PostFields> & { updatedAt?: Date; deletedAt?: Date },
): Promise<boolean> {
  const updated = await db
    .update(post)
    .set(changes)
    .where(
      and(
        eq(post.id, postId),
        eq(post.authorId, authorId),
        isNull(post.deletedAt),
      ),
    )
    .returning({ id: post.id });
  return updated.length > 0;
}

/** Returns false when the person was already attending. */
export async function insertAttendee(
  db: Database,
  postId: string,
  userId: string,
  now: Date,
): Promise<boolean> {
  const inserted = await db
    .insert(postAttendee)
    .values({ postId, userId, createdAt: now })
    .onConflictDoNothing()
    .returning({ postId: postAttendee.postId });
  return inserted.length > 0;
}

export async function deleteAttendee(
  db: Database,
  postId: string,
  userId: string,
) {
  await db
    .delete(postAttendee)
    .where(
      and(eq(postAttendee.postId, postId), eq(postAttendee.userId, userId)),
    );
}
