import type { Database } from "../db/client";
import type {
  NotificationEvent,
  Notifier,
} from "../notifications/notification";
import type { Person, PersonRow, PersonViewer } from "../profiles/person";
import {
  deleteAttendee,
  findPostFor,
  insertAttendee,
  insertPost,
  listAttendeeIds,
  listAttendeePreviews,
  type Post,
  type PostFields,
  type PostRow,
  updateLivePost,
} from "./forum-store";

export interface PostView {
  id: string;
  forumId: string;
  title: string;
  description: string | null;
  location: string | null;
  startsAt: string;
  endsAt: string | null;
  createdAt: string;
  updatedAt: string;
  author: Person;
  attendeeCount: number;
  attendeePreview: Person[];
  attending: boolean;
  isAuthor: boolean;
  edited: boolean;
  past: boolean;
  cancelled: boolean;
}

export type PostActionError =
  | "not_found"
  | "not_author"
  | "post_cancelled"
  | "event_over"
  | "invalid_times";

export type PostActionResult =
  | { ok: true; post: PostView }
  | { ok: false; error: PostActionError };

/** Over once `endsAt` passes, or `startsAt` when there is no end time. */
export function isPast(
  row: Pick<Post, "startsAt" | "endsAt">,
  now: Date,
): boolean {
  return (row.endsAt ?? row.startsAt).getTime() <= now.getTime();
}

export function timesInOrder(row: Pick<Post, "startsAt" | "endsAt">): boolean {
  return row.endsAt === null || row.endsAt.getTime() >= row.startsAt.getTime();
}

export async function viewPost(
  viewPerson: PersonViewer,
  row: PostRow,
  viewerId: string,
  preview: PersonRow[],
  now: Date,
): Promise<PostView> {
  const { post } = row;
  const [author, attendeePreview] = await Promise.all([
    viewPerson(row.author),
    Promise.all(preview.map(viewPerson)),
  ]);
  return {
    id: post.id,
    forumId: post.forumId,
    title: post.title,
    description: post.description,
    location: post.location,
    startsAt: post.startsAt.toISOString(),
    endsAt: post.endsAt?.toISOString() ?? null,
    createdAt: post.createdAt.toISOString(),
    updatedAt: post.updatedAt.toISOString(),
    author,
    attendeeCount: post.attendeeCount,
    attendeePreview,
    attending: row.attending,
    isAuthor: post.authorId === viewerId,
    edited: post.updatedAt.getTime() > post.createdAt.getTime(),
    past: isPast(post, now),
    cancelled: post.deletedAt !== null,
  };
}

export async function viewPostRows(
  db: Database,
  viewPerson: PersonViewer,
  rows: PostRow[],
  viewerId: string,
  now: Date,
): Promise<PostView[]> {
  const previews = await listAttendeePreviews(
    db,
    rows.map((row) => row.post.id),
  );
  return Promise.all(
    rows.map((row) =>
      viewPost(viewPerson, row, viewerId, previews.get(row.post.id) ?? [], now),
    ),
  );
}

export async function getPostView(
  db: Database,
  viewPerson: PersonViewer,
  postId: string,
  viewerId: string,
  now: Date,
): Promise<PostView | null> {
  const row = await findPostFor(db, postId, viewerId);
  if (!row) return null;
  const [view] = await viewPostRows(db, viewPerson, [row], viewerId, now);
  return view ?? null;
}

async function respondWithPost(
  db: Database,
  viewPerson: PersonViewer,
  postId: string,
  viewerId: string,
  now: Date,
): Promise<PostActionResult> {
  const view = await getPostView(db, viewPerson, postId, viewerId, now);
  return view ? { ok: true, post: view } : { ok: false, error: "not_found" };
}

/** The forum must be one the author can see. */
export async function createPost(
  db: Database,
  viewPerson: PersonViewer,
  forumId: string,
  authorId: string,
  fields: PostFields,
  now: Date,
): Promise<PostView> {
  const postId = await insertPost(db, { ...fields, forumId, authorId }, now);
  const view = await getPostView(db, viewPerson, postId, authorId, now);
  if (!view) throw new Error("Created post is not visible to its author");
  return view;
}

/** Explains why a change to a live post by its author did not apply. */
async function refusal(
  db: Database,
  postId: string,
  userId: string,
): Promise<PostActionResult> {
  const row = await findPostFor(db, postId, userId);
  if (!row) return { ok: false, error: "not_found" };
  if (row.post.authorId !== userId) return { ok: false, error: "not_author" };
  return { ok: false, error: "post_cancelled" };
}

async function notifyAttendees(
  db: Database,
  notifier: Notifier,
  row: Pick<Post, "id" | "forumId" | "authorId">,
  kind: "post_updated" | "post_cancelled",
) {
  const event: NotificationEvent = {
    kind,
    postId: row.id,
    forumId: row.forumId,
  };
  const attendeeIds = await listAttendeeIds(db, row.id);
  await Promise.all(
    attendeeIds
      .filter((id) => id !== row.authorId)
      .map((id) => notifier.send(id, event)),
  );
}

export async function editPost(
  db: Database,
  viewPerson: PersonViewer,
  notifier: Notifier,
  postId: string,
  userId: string,
  changes: Partial<PostFields>,
  now: Date,
): Promise<PostActionResult> {
  const row = await findPostFor(db, postId, userId);
  if (!row) return { ok: false, error: "not_found" };
  if (row.post.authorId !== userId) return { ok: false, error: "not_author" };
  if (row.post.deletedAt) return { ok: false, error: "post_cancelled" };
  if (!timesInOrder({ ...row.post, ...changes })) {
    return { ok: false, error: "invalid_times" };
  }
  const updated = await updateLivePost(db, postId, userId, {
    ...changes,
    updatedAt: now,
  });
  if (!updated) return refusal(db, postId, userId);
  const result = await respondWithPost(db, viewPerson, postId, userId, now);
  if (result.ok) {
    await notifyAttendees(
      db,
      notifier,
      { id: postId, forumId: result.post.forumId, authorId: userId },
      "post_updated",
    );
  }
  return result;
}

/** Soft-deletes the post. Attendee rows stay, so attendees can be told. */
export async function cancelPost(
  db: Database,
  viewPerson: PersonViewer,
  notifier: Notifier,
  postId: string,
  userId: string,
  now: Date,
): Promise<PostActionResult> {
  const updated = await updateLivePost(db, postId, userId, { deletedAt: now });
  if (!updated) return refusal(db, postId, userId);
  const result = await respondWithPost(db, viewPerson, postId, userId, now);
  if (result.ok) {
    await notifyAttendees(
      db,
      notifier,
      { id: postId, forumId: result.post.forumId, authorId: userId },
      "post_cancelled",
    );
  }
  return result;
}

/** Tells the author about a new attendee, unless the author is the attendee. */
export async function attendPost(
  db: Database,
  viewPerson: PersonViewer,
  notifier: Notifier,
  postId: string,
  userId: string,
  now: Date,
): Promise<PostActionResult> {
  const row = await findPostFor(db, postId, userId);
  if (!row) return { ok: false, error: "not_found" };
  if (row.post.deletedAt) return { ok: false, error: "post_cancelled" };
  if (isPast(row.post, now)) return { ok: false, error: "event_over" };
  const added = await insertAttendee(db, postId, userId, now);
  if (added && row.post.authorId !== userId) {
    await notifier.send(row.post.authorId, {
      kind: "post_rsvp",
      postId,
      forumId: row.post.forumId,
    });
  }
  return respondWithPost(db, viewPerson, postId, userId, now);
}

export async function leavePost(
  db: Database,
  viewPerson: PersonViewer,
  postId: string,
  userId: string,
  now: Date,
): Promise<PostActionResult> {
  const row = await findPostFor(db, postId, userId);
  if (!row) return { ok: false, error: "not_found" };
  await deleteAttendee(db, postId, userId);
  return respondWithPost(db, viewPerson, postId, userId, now);
}
