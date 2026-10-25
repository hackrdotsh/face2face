import { describe, expect, it } from "vitest";
import { APIClient, type RequestRecord, type TokenStore } from "./client";
import { APIError } from "./errors";

function memoryTokens(initial: string | null = null): TokenStore {
  let token = initial;
  return { get: () => token, set: (next) => (token = next) };
}

function fakeFetch(response: () => Response, calls: Request[]): typeof fetch {
  return async (input, init) => {
    calls.push(new Request(input, init));
    return response();
  };
}

describe("APIClient", () => {
  it("saves the session token the server returns", async () => {
    const tokens = memoryTokens();
    const client = new APIClient({
      serverURL: () => "http://api.test",
      tokens,
      fetch: fakeFetch(
        () =>
          new Response("{}", { headers: { "set-auth-token": "signed.token" } }),
        [],
      ),
    });
    await client.send({ path: "api/auth/sign-in/email-otp", body: {} });
    expect(tokens.get()).toBe("signed.token");
  });

  it("sends the bearer token only on authenticated requests, without cookies", async () => {
    const calls: Request[] = [];
    const client = new APIClient({
      serverURL: () => "http://api.test",
      tokens: memoryTokens("signed.token"),
      fetch: fakeFetch(() => new Response("{}"), calls),
    });
    await client.send({ path: "/api/me", authenticated: true });
    await client.send({ path: "health" });
    expect(calls.map((call) => call.headers.get("Authorization"))).toEqual([
      "Bearer signed.token",
      null,
    ]);
    expect(calls[0]?.url).toBe("http://api.test/api/me");
    expect(calls[0]?.credentials).toBe("omit");
  });

  it("includes cookies when a request asks for them", async () => {
    const calls: Request[] = [];
    const client = new APIClient({
      serverURL: () => "http://api.test",
      tokens: memoryTokens(),
      fetch: fakeFetch(() => new Response("{}"), calls),
    });
    await client.send({
      path: "api/auth/passkey/generate-register-options",
      query: { name: "Laptop" },
      withCookies: true,
    });
    expect(calls[0]?.credentials).toBe("include");
    expect(calls[0]?.url).toBe(
      "http://api.test/api/auth/passkey/generate-register-options?name=Laptop",
    );
  });

  it("throws mapped errors and records the exchange", async () => {
    const records: RequestRecord[] = [];
    const client = new APIClient({
      serverURL: () => "http://api.test",
      tokens: memoryTokens(),
      onRecord: (record) => records.push(record),
      fetch: fakeFetch(
        () =>
          new Response(JSON.stringify({ error: "onboarding_required" }), {
            status: 403,
          }),
        [],
      ),
    });
    await expect(
      client.send({ path: "api/coordinator" }),
    ).rejects.toMatchObject({
      kind: "onboardingRequired",
    });
    expect(records.at(-1)).toMatchObject({
      status: 403,
      responseBody: { error: "onboarding_required" },
    });
  });

  it("reports a network failure", async () => {
    const client = new APIClient({
      serverURL: () => "http://api.test",
      tokens: memoryTokens(),
      fetch: async () => {
        throw new TypeError("Failed to fetch");
      },
    });
    const error: unknown = await client
      .send({ path: "health" })
      .catch((caught) => caught);
    expect(error).toBeInstanceOf(APIError);
    expect((error as APIError).kind).toBe("network");
  });
});
