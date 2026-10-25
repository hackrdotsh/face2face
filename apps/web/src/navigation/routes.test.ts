import { describe, expect, it } from "vitest";
import { defaultRoute, hrefFor, parseRoute } from "./routes";

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
