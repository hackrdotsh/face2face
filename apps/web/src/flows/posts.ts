import type { Post } from "@/api/types";

/** The post as it will look once the RSVP goes through. */
export function withAttending(post: Post, attending: boolean): Post {
  if (post.attending === attending) return post;
  return {
    ...post,
    attending,
    attendeeCount: post.attendeeCount + (attending ? 1 : -1),
  };
}

export function replacePost(posts: Post[], next: Post): Post[] {
  return posts.map((post) => (post.id === next.id ? next : post));
}

/** Turns an ISO time into a `datetime-local` value in the browser's zone. */
export function toLocalInput(iso: string | null): string {
  if (!iso) return "";
  const date = new Date(iso);
  const offsetMs = date.getTimezoneOffset() * 60_000;
  return new Date(date.getTime() - offsetMs).toISOString().slice(0, 16);
}

/** Turns a `datetime-local` value into an ISO time. Blank means no time. */
export function fromLocalInput(value: string): string | null {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

export function formatEventTime(post: Pick<Post, "startsAt" | "endsAt">) {
  const format = (iso: string) =>
    new Date(iso).toLocaleString([], {
      weekday: "short",
      month: "short",
      day: "numeric",
      hour: "numeric",
      minute: "2-digit",
    });
  return post.endsAt
    ? `${format(post.startsAt)} to ${format(post.endsAt)}`
    : format(post.startsAt);
}
