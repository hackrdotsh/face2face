import { describe, expect, it } from "vitest";
import type { Post } from "@/api/types";
import {
  fromLocalInput,
  replacePost,
  toLocalInput,
  withAttending,
} from "./posts";

const post: Post = {
  id: "p1",
  forumId: "coffee",
  title: "Cupping",
  description: null,
  location: null,
  startsAt: "2030-01-01T10:00:00.000Z",
  endsAt: null,
  createdAt: "2026-10-24T12:00:00.000Z",
  updatedAt: "2026-10-24T12:00:00.000Z",
  author: { userId: "a", name: "Ava", image: null },
  attendeeCount: 2,
  attendeePreview: [],
  attending: false,
  isAuthor: false,
  edited: false,
  past: false,
  cancelled: false,
};

describe("posts", () => {
  it("adjusts the count only when attending changes", () => {
    expect(withAttending(post, true)).toMatchObject({
      attending: true,
      attendeeCount: 3,
    });
    expect(withAttending(post, false)).toBe(post);
    expect(
      withAttending({ ...post, attending: true }, false).attendeeCount,
    ).toBe(1);
  });

  it("replaces a post by ID", () => {
    const other = { ...post, id: "p2" };
    const next = { ...post, title: "Tasting" };
    expect(replacePost([post, other], next)).toEqual([next, other]);
  });

  it("round-trips a local time input", () => {
    const iso = "2030-01-01T10:30:00.000Z";
    expect(fromLocalInput(toLocalInput(iso))).toBe(iso);
    expect(toLocalInput(null)).toBe("");
    expect(fromLocalInput("")).toBeNull();
  });
});
