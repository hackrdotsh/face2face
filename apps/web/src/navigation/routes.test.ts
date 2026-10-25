import { describe, expect, it } from "vitest";
import { defaultRoute, hrefFor, navPageOf, parseRoute } from "./routes";

describe("routes", () => {
  it("reads each page", () => {
    expect(parseRoute("#/notifications")).toEqual({ page: "notifications" });
    expect(parseRoute("#/chats")).toEqual({ page: "chats", chatId: null });
    expect(parseRoute("#/chats/abc")).toEqual({ page: "chats", chatId: "abc" });
  });

  it("goes to the default page for an empty or unknown hash", () => {
    expect(parseRoute("")).toEqual(defaultRoute);
    expect(parseRoute("#/nope")).toEqual(defaultRoute);
  });

  it("round-trips a chat ID that needs escaping", () => {
    const route = { page: "chats" as const, chatId: "a/b c" };
    expect(parseRoute(hrefFor(route))).toEqual(route);
  });
});

describe("forum routes", () => {
  it("reads the forum list, one forum, and one post", () => {
    expect(parseRoute("#/forums")).toEqual({ page: "forums", forumId: null });
    expect(parseRoute("#/forums/coffee")).toEqual({
      page: "forums",
      forumId: "coffee",
    });
    expect(parseRoute("#/posts/p1")).toEqual({ page: "post", postId: "p1" });
  });

  it("needs a post ID", () => {
    expect(parseRoute("#/posts")).toEqual(defaultRoute);
  });

  it("highlights Forums in the nav for a post", () => {
    expect(navPageOf({ page: "post", postId: "p1" })).toBe("forums");
    expect(navPageOf({ page: "forums", forumId: null })).toBe("forums");
  });

  it("round-trips IDs that need escaping", () => {
    for (const route of [
      { page: "forums" as const, forumId: "a/b c" },
      { page: "post" as const, postId: "x/y z" },
    ]) {
      expect(parseRoute(hrefFor(route))).toEqual(route);
    }
  });
});
