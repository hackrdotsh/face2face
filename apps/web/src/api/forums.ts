import type { APIClient } from "./client";
import type { Forum, ForumPerson, Post, PostInput, PostPage } from "./types";

export async function listForums(client: APIClient) {
  const { forums } = await client.send<{ forums: Forum[] }>({
    path: "api/forums",
    authenticated: true,
  });
  return forums;
}

/** Newest first. Pass the last post ID of a page as `before` for the next one. */
export function listPosts(client: APIClient, forumId: string, before?: string) {
  return client.send<PostPage>({
    path: `api/forums/${encodeURIComponent(forumId)}/posts`,
    query: before ? { before } : undefined,
    authenticated: true,
  });
}

export async function createPost(
  client: APIClient,
  forumId: string,
  input: PostInput,
) {
  const { post } = await client.send<{ post: Post }>({
    path: `api/forums/${encodeURIComponent(forumId)}/posts`,
    body: input,
    authenticated: true,
  });
  return post;
}

export async function getPost(client: APIClient, postId: string) {
  const { post } = await client.send<{ post: Post }>({
    path: postPath(postId),
    authenticated: true,
  });
  return post;
}

export async function editPost(
  client: APIClient,
  postId: string,
  changes: Partial<PostInput>,
) {
  const { post } = await client.send<{ post: Post }>({
    path: postPath(postId),
    method: "PATCH",
    body: changes,
    authenticated: true,
  });
  return post;
}

/** Cancels the event. Attendees are told, and the post stays readable. */
export async function cancelPost(client: APIClient, postId: string) {
  const { post } = await client.send<{ post: Post }>({
    path: postPath(postId),
    method: "DELETE",
    authenticated: true,
  });
  return post;
}

export async function setAttending(
  client: APIClient,
  postId: string,
  attending: boolean,
) {
  const { post } = await client.send<{ post: Post }>({
    path: `${postPath(postId)}/rsvp`,
    method: attending ? "PUT" : "DELETE",
    authenticated: true,
  });
  return post;
}

export async function listAttendees(client: APIClient, postId: string) {
  const { attendees } = await client.send<{ attendees: ForumPerson[] }>({
    path: `${postPath(postId)}/attendees`,
    authenticated: true,
  });
  return attendees;
}

function postPath(postId: string) {
  return `api/posts/${encodeURIComponent(postId)}`;
}

/**
 * Upcoming posts from all of the person's forums, soonest first. Pass the last
 * post ID of a page as `after` for the next one.
 */
export function listUpcomingPosts(client: APIClient, after?: string) {
  return client.send<PostPage>({
    path: "api/posts",
    query: after ? { after } : undefined,
    authenticated: true,
  });
}
