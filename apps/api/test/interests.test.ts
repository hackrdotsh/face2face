import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import {
  bearerHeaders,
  callAPI,
  completeOnboarding,
  postJSON,
  signInWithEmailCode,
} from "./helpers";

interface InterestChoice {
  id: string;
  memberCount: number;
  selected: boolean;
}

beforeEach(async () => {
  await env.DB.prepare("DELETE FROM rate_limit").run();
  await postJSON("/api/dev/reset", {});
  await postJSON("/api/dev/seed", {});
});

async function onboardedPerson(email: string) {
  const token = await signInWithEmailCode(email);
  await completeOnboarding(token);
  return bearerHeaders(token);
}

function putInterests(headers: Record<string, string>, interestIds: unknown) {
  return callAPI("/api/interests", {
    method: "PUT",
    headers: { ...headers, "Content-Type": "application/json" },
    body: JSON.stringify({ interestIds }),
  });
}

async function choices(headers: Record<string, string>) {
  const response = await callAPI("/api/interests", { headers });
  expect(response.status).toBe(200);
  return (await response.json<{ interests: InterestChoice[] }>()).interests;
}

describe("interests API", () => {
  it("requires a finished profile", async () => {
    expect((await callAPI("/api/interests")).status).toBe(401);
    const token = await signInWithEmailCode("unfinished@example.test");
    const response = await callAPI("/api/interests", {
      headers: bearerHeaders(token),
    });
    expect(response.status).toBe(403);
  });

  it("replaces the person's interests and updates member counts", async () => {
    const headers = await onboardedPerson("picker@example.test");
    const before = await choices(headers);
    expect(before.every((choice) => !choice.selected)).toBe(true);
    const coffeeBefore = before.find((choice) => choice.id === "coffee");

    expect((await putInterests(headers, ["coffee", "yoga"])).status).toBe(200);
    const picked = await choices(headers);
    expect(
      picked.filter((choice) => choice.selected).map((choice) => choice.id),
    ).toEqual(["coffee", "yoga"]);
    expect(picked.find((choice) => choice.id === "coffee")?.memberCount).toBe(
      (coffeeBefore?.memberCount ?? 0) + 1,
    );

    await putInterests(headers, ["yoga"]);
    const after = await choices(headers);
    expect(after.find((choice) => choice.id === "coffee")?.memberCount).toBe(
      coffeeBefore?.memberCount,
    );
  });

  it("rejects unknown, repeated, or too many interests", async () => {
    const headers = await onboardedPerson("strict@example.test");
    expect((await putInterests(headers, ["skydiving"])).status).toBe(400);
    expect((await putInterests(headers, ["coffee", "coffee"])).status).toBe(
      400,
    );
    const all = (await choices(headers)).map((choice) => choice.id);
    expect((await putInterests(headers, all.slice(0, 11))).status).toBe(400);
    expect((await putInterests(headers, "coffee")).status).toBe(400);
  });

  it("uses the new interests in the next encounter", async () => {
    const headers = await onboardedPerson("encounter@example.test");
    await putInterests(headers, ["jazz", "reading", "yoga"]);
    const me = await (await callAPI("/api/me", { headers })).json<{
      user: { id: string };
    }>();
    const response = await postJSON("/api/dev/encounters", {
      firstUserId: me.user.id,
      secondUserId: "seed-cleo",
    });
    const { connection } = await response.json<{
      connection: { sharedInterests: string[] };
    }>();
    expect(connection.sharedInterests).toEqual(["jazz", "reading"]);
  });
});
