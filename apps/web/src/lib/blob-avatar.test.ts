import { describe, expect, it } from "vitest";
import fixtures from "../../../../docs/fixtures/blob-avatar.json";
import {
  type BlobAvatar,
  blobAvatar,
  blobPath,
  decodeSeed,
} from "./blob-avatar";

const tolerance = 9;

function expectClose(actual: unknown, expected: unknown) {
  if (typeof expected === "number") {
    expect(actual).toBeCloseTo(expected, tolerance);
    return;
  }
  if (expected && typeof expected === "object") {
    const entries = Object.entries(expected);
    expect(Object.keys(actual as object)).toHaveLength(entries.length);
    for (const [key, value] of entries) {
      expectClose((actual as Record<string, unknown>)[key], value);
    }
    return;
  }
  expect(actual).toEqual(expected);
}

describe("blob avatars", () => {
  it.each(fixtures)(
    "matches the shared fixture for $seed",
    ({ seed, avatar }) => {
      expectClose(blobAvatar(decodeSeed(seed)), avatar);
    },
  );

  it("closes the curve where it starts", () => {
    for (const { seed } of fixtures) {
      const avatar: BlobAvatar = blobAvatar(decodeSeed(seed));
      expect(avatar.curves.at(-1)?.end).toEqual(avatar.start);
    }
  });

  it("writes a closed SVG path scaled to the box", () => {
    const path = blobPath(
      blobAvatar(decodeSeed("AAAAAAAAAAAAAAAAAAAAAA")),
      100,
    );
    expect(path).toMatch(/^M50 16C.*Z$/);
    expect(path.match(/C/g)).toHaveLength(6);
  });
});
