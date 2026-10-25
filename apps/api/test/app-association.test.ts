import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import app from "../src/index";

const path = "https://f2f.rocky.systems/.well-known/apple-app-site-association";

describe("Apple app association", () => {
  it("publishes the configured native app as a web credential owner without authentication", async () => {
    const response = await app.request(
      path,
      {},
      {
        ...env,
        APPLE_APP_ID: "GFQG7YBAYY.systems.rocky.face2face",
      },
    );

    expect(response.status).toBe(200);
    expect(response.headers.get("Content-Type")).toContain("application/json");
    expect(response.headers.get("Cache-Control")).toBe("public, max-age=3600");
    expect(await response.json()).toEqual({
      webcredentials: { apps: ["GFQG7YBAYY.systems.rocky.face2face"] },
    });
  });

  it("does not publish an association when no app is configured", async () => {
    const response = await app.request(path, {}, { ...env, APPLE_APP_ID: "" });
    expect(response.status).toBe(404);
  });
});
