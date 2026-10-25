import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { textField } from "../src/onboarding/field-builders";
import { onboardingFields } from "../src/onboarding/fields";
import { describeOnboarding } from "../src/onboarding/onboarding";
import type { ProfileSnapshot } from "../src/onboarding/profile-store";
import { bearerHeaders, callAPI, signInWithEmailCode } from "./helpers";

beforeEach(async () => {
  await env.DB.prepare("DELETE FROM rate_limit").run();
});

function patchOnboarding(token: string, values: Record<string, unknown>) {
  return callAPI("/api/onboarding", {
    method: "PATCH",
    headers: { ...bearerHeaders(token), "Content-Type": "application/json" },
    body: JSON.stringify({ values }),
  });
}

interface OnboardingResponse {
  complete: boolean;
  fields: { key: string; value: unknown; options?: { id: string }[] }[];
}

describe("onboarding API", () => {
  it("requires a session", async () => {
    expect((await callAPI("/api/onboarding")).status).toBe(401);
  });

  it("describes every field with no values for a new account", async () => {
    const token = await signInWithEmailCode("new@example.test");
    const response = await callAPI("/api/onboarding", {
      headers: bearerHeaders(token),
    });
    const state = await response.json<OnboardingResponse>();
    expect(state.complete).toBe(false);
    expect(state.fields.map((field) => [field.key, field.value])).toEqual([
      ["name", null],
      ["birthDate", null],
      ["gender", null],
      ["photo", null],
    ]);
    const gender = state.fields.find((field) => field.key === "gender");
    expect(gender?.options?.map((option) => option.id)).toEqual([
      "male",
      "female",
      "other",
    ]);
  });

  it("saves fields across requests and completes when every required field has a value", async () => {
    const token = await signInWithEmailCode("steps@example.test");
    const first = await patchOnboarding(token, { name: "  Sam  " });
    expect((await first.json<OnboardingResponse>()).complete).toBe(false);
    const second = await patchOnboarding(token, {
      birthDate: "1995-02-03",
      gender: { optionId: "male", description: "ignored for this option" },
    });
    const state = await second.json<OnboardingResponse>();
    expect(state.complete).toBe(true);
    expect(state.fields.map((field) => [field.key, field.value])).toEqual([
      ["name", "Sam"],
      ["birthDate", "1995-02-03"],
      ["gender", { optionId: "male" }],
      ["photo", null],
    ]);
    const me = await callAPI("/api/me", { headers: bearerHeaders(token) });
    expect(await me.json()).toMatchObject({
      user: { name: "Sam" },
      onboardingComplete: true,
    });
  });

  it("stores a custom description for the other gender option", async () => {
    const token = await signInWithEmailCode("other@example.test");
    const response = await patchOnboarding(token, {
      gender: { optionId: "other", description: "Genderfluid" },
    });
    const state = await response.json<OnboardingResponse>();
    expect(state.fields.find((field) => field.key === "gender")?.value).toEqual(
      { optionId: "other", description: "Genderfluid" },
    );
  });

  it("rejects invalid values without saving any of them", async () => {
    const token = await signInWithEmailCode("invalid@example.test");
    const response = await patchOnboarding(token, {
      name: "Valid name",
      birthDate: "2015-01-01",
      gender: { optionId: "other" },
      favouriteColour: "blue",
    });
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({
      error: "invalid_fields",
      fields: {
        birthDate: "You must be 18 or older to use face2face.",
        gender: "Describe your gender.",
        favouriteColour: "This field is not part of onboarding.",
      },
    });
    const state = await (
      await callAPI("/api/onboarding", { headers: bearerHeaders(token) })
    ).json<OnboardingResponse>();
    expect(
      state.fields.find((field) => field.key === "name")?.value,
    ).toBeNull();
  });

  it("rejects unknown gender options and malformed dates", async () => {
    const token = await signInWithEmailCode("malformed@example.test");
    const response = await patchOnboarding(token, {
      birthDate: "1990-02-30",
      gender: { optionId: "unknown" },
    });
    expect(await response.json()).toEqual({
      error: "invalid_fields",
      fields: {
        birthDate: "Enter a date as YYYY-MM-DD.",
        gender: "Choose an option.",
      },
    });
  });

  it("rejects a body without a values object", async () => {
    const token = await signInWithEmailCode("body@example.test");
    const response = await callAPI("/api/onboarding", {
      method: "PATCH",
      headers: { ...bearerHeaders(token), "Content-Type": "application/json" },
      body: "[]",
    });
    expect(response.status).toBe(400);
  });
});

describe("onboarding field registry", () => {
  const completedSnapshot: ProfileSnapshot = {
    name: "Sam",
    birthDate: "1995-02-03",
    genderId: "male",
    genderDescription: null,
    genderOptions: [],
    photo: null,
  };
  const context = { snapshot: completedSnapshot, today: "2026-10-24" };

  it("reopens onboarding when a new required field is added", () => {
    expect(describeOnboarding(onboardingFields, context).complete).toBe(true);
    const withNewField = [
      ...onboardingFields,
      textField({
        key: "pronouns",
        label: "Pronouns",
        required: true,
        maxLength: 30,
        emptyMessage: "Enter your pronouns.",
        read: () => null,
        write: () => ({}),
      }),
    ];
    expect(describeOnboarding(withNewField, context).complete).toBe(false);
  });

  it("allows birth dates up to exactly 18 years before today", () => {
    const state = describeOnboarding(onboardingFields, context);
    const birthDate = state.fields.find((field) => field.key === "birthDate");
    expect(birthDate?.constraints?.latestDate).toBe("2008-10-24");
  });
});
