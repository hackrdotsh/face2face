import { describe, expect, it } from "vitest";
import { APIError } from "./errors";

describe("APIError.from", () => {
  it.each([
    [
      400,
      { error: "invalid_fields", fields: { name: "Enter your name." } },
      "invalidFields",
    ],
    [400, { code: "INVALID_OTP" }, "invalidCode"],
    [400, { code: "OTP_EXPIRED" }, "invalidCode"],
    [403, { code: "TOO_MANY_ATTEMPTS" }, "invalidCode"],
    [401, { code: "INVALID_EMAIL_OR_PASSWORD" }, "invalidCredentials"],
    [401, { error: "unauthorized" }, "unauthenticated"],
    [403, { code: "EMAIL_NOT_VERIFIED" }, "emailNotVerified"],
    [403, { error: "onboarding_required" }, "onboardingRequired"],
    [429, null, "rateLimited"],
    [500, "oops", "server"],
  ] as const)("maps HTTP %i %j to %s", (status, body, kind) => {
    expect(APIError.from(status, body).kind).toBe(kind);
  });

  it("keeps field messages from the server", () => {
    const error = APIError.from(400, {
      error: "invalid_fields",
      fields: { name: "Enter your name.", ignored: 3 },
    });
    expect(error.fields).toEqual({ name: "Enter your name." });
  });

  it("describes unexpected statuses", () => {
    expect(APIError.from(502, null).message).toBe(
      "The API returned HTTP 502. Try again.",
    );
    expect(APIError.from(400, null).message).toBe(
      "Check what you entered, then try again.",
    );
  });
});
