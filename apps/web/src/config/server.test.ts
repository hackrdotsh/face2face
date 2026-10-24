import { describe, expect, it } from "vitest";
import { normalizeServerURL } from "./server";

describe("normalizeServerURL", () => {
  it.each([
    ["https://f2f.rocky.systems", "https://f2f.rocky.systems"],
    ["https://f2f.rocky.systems/", "https://f2f.rocky.systems"],
    [" http://localhost:8080 ", "http://localhost:8080"],
    ["https://f2f.rocky.systems/api", null],
    ["https://user:pass@f2f.rocky.systems", null],
    ["ftp://f2f.rocky.systems", null],
    ["not a url", null],
  ])("normalizes %j to %j", (input, expected) => {
    expect(normalizeServerURL(input)).toBe(expected);
  });
});
