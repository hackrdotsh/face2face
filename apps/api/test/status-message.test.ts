import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { bearerHeaders, callAPI, postJSON, requireAuthToken } from "./helpers";

const ava = "seed-ava";
const ben = "seed-ben";
const avaSeedStatus = "Looking for a bouldering partner this weekend";

type Headers = Record<string, string>;

interface ConnectionView {
  id: string;
  status: string;
  them: { statusMessage: string | null } | null;
}

beforeEach(async () => {
  await env.DB.prepare("DELETE FROM rate_limit").run();
  await postJSON("/api/dev/reset", {});
  await postJSON("/api/dev/seed", {});
});

async function signInAs(userId: string): Promise<Headers> {
  const response = await postJSON("/api/auth/sign-in/email", {
    email: `${userId.replace("seed-", "")}@seed.face2face.test`,
    password: "face2face-seed-password",
  });
  return bearerHeaders(requireAuthToken(response));
}

function putStatus(headers: Headers, statusMessage: unknown) {
  return callAPI("/api/profile/status", {
    method: "PUT",
    headers: { ...headers, "Content-Type": "application/json" },
    body: JSON.stringify({ statusMessage }),
  });
}

async function myStatus(headers: Headers): Promise<string | null> {
  const response = await callAPI("/api/me", { headers });
  return (await response.json<{ user: { statusMessage: string | null } }>())
    .user.statusMessage;
}

async function connectAvaAndBen(): Promise<{
  id: string;
  avaHeaders: Headers;
  benHeaders: Headers;
}> {
  const encounter = await postJSON("/api/dev/encounters", {
    firstUserId: ava,
    secondUserId: ben,
  });
  const id =
    (await encounter.json<{ connection: { id: string } | null }>()).connection
      ?.id ?? "";
  const avaHeaders = await signInAs(ava);
  const benHeaders = await signInAs(ben);
  for (const headers of [avaHeaders, benHeaders]) {
    await postJSON(
      `/api/connections/${id}/decision`,
      { decision: "accepted" },
      headers,
    );
  }
  return { id, avaHeaders, benHeaders };
}

async function benSeesAva(benHeaders: Headers): Promise<ConnectionView> {
  const response = await callAPI("/api/connections", { headers: benHeaders });
  const { connections } = await response.json<{
    connections: ConnectionView[];
  }>();
  const [view] = connections;
  if (!view) throw new Error("Missing connection");
  return view;
}

describe("status messages", () => {
  it("saves one trimmed line and clears on empty text", async () => {
    const headers = await signInAs(ava);
    const saved = await putStatus(headers, "  Out for\n coffee  ");
    expect(saved.status).toBe(200);
    expect(await saved.json()).toEqual({ statusMessage: "Out for coffee" });
    expect(await myStatus(headers)).toBe("Out for coffee");

    expect(await (await putStatus(headers, "   ")).json()).toEqual({
      statusMessage: null,
    });
    expect(await myStatus(headers)).toBeNull();
  });

  it("allows 80 code points and rejects more", async () => {
    const headers = await signInAs(ava);
    expect((await putStatus(headers, "🌲".repeat(80))).status).toBe(200);
    const tooLong = await putStatus(headers, "a".repeat(81));
    expect(tooLong.status).toBe(400);
    expect(await tooLong.json()).toEqual({ error: "status_too_long" });
    expect((await putStatus(headers, 42)).status).toBe(400);
    expect(await myStatus(headers)).toBe("🌲".repeat(80));
  });

  it("requires a session", async () => {
    expect((await putStatus({}, "Hi")).status).toBe(401);
  });

  it("shows the status only to public connections", async () => {
    const { id, avaHeaders, benHeaders } = await connectAvaAndBen();
    const privateView = await benSeesAva(benHeaders);
    expect(privateView.status).toBe("private");
    expect(JSON.stringify(privateView)).not.toContain(avaSeedStatus);

    await postJSON(`/api/connections/${id}/public`, {}, avaHeaders);
    await postJSON(`/api/connections/${id}/public`, {}, benHeaders);
    expect((await benSeesAva(benHeaders)).them?.statusMessage).toBe(
      avaSeedStatus,
    );

    await putStatus(avaHeaders, null);
    expect((await benSeesAva(benHeaders)).them?.statusMessage).toBeNull();
  });
});
