import { randomUUID } from "node:crypto";

const address = new URL(process.argv[2] ?? "http://127.0.0.1:8080");
if (
  !["localhost", "127.0.0.1", "[::1]"].includes(address.hostname) ||
  !["http:", "https:"].includes(address.protocol) ||
  address.username ||
  address.password ||
  address.search ||
  address.hash ||
  address.pathname !== "/"
) {
  throw new Error(
    "Use a loopback API base URL. This test signs in as two local seed people.",
  );
}
const base = address.origin;
const seedEmail = (id) => `${id.replace("seed-", "")}@seed.face2face.test`;

function check(condition, message) {
  if (!condition) throw new Error(message);
}
function request(path, init = {}, credential) {
  return fetch(base + "/api/" + path, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      Origin: "face2face://",
      ...(credential ? { Authorization: "Bearer " + credential } : {}),
    },
    signal: AbortSignal.timeout(10_000),
  });
}
function post(path, value, credential) {
  return request(
    path,
    { method: "POST", body: JSON.stringify(value) },
    credential,
  );
}
async function json(response, message) {
  check(response.status === 200, message + " (HTTP " + response.status + ")");
  return response.json();
}
async function signIn(id, password) {
  const response = await post("auth/sign-in/email", {
    email: seedEmail(id),
    password,
  });
  const credential = response.headers.get("set-auth-token");
  await json(response, `Could not sign in as ${id}`);
  check(credential, "Missing signed account credential");
  return { id, credential };
}
async function pendingChances(client) {
  const { connections } = await json(
    await request("connections", {}, client.credential),
    "Connections request failed",
  );
  return connections.filter((row) => row.status === "pending");
}
function observe(client, own, peer, observationId = randomUUID()) {
  return post(
    "discovery/observe",
    { sessionId: own.sessionId, peerToken: peer.token, observationId },
    client.credential,
  );
}
function assertAnonymous(body, names) {
  for (const value of names) {
    check(!body.includes(value), `A receipt disclosed ${value}`);
  }
}

const { password } = await json(
  await post("dev/seed", {}),
  "Seeding failed. Is DEV_TOOLS true?",
);
const people = ["seed-ava", "seed-ben"];
const { connections: rows } = await json(
  await request("dev/connections"),
  "Dev connections request failed",
);
for (const row of rows) {
  const pair = [row.userLowId, row.userHighId];
  if (!people.every((id) => pair.includes(id))) continue;
  check(
    row.status === "pending" ||
      row.status === "expired" ||
      row.status === "blocked",
    "Ava and Ben are already connected. Run POST /api/dev/reset first.",
  );
  if (row.status === "pending") {
    await json(
      await post(`dev/connections/${row.id}/expire`, {}),
      "Could not expire an earlier chance",
    );
  }
}

const clients = [];
const leases = [];
try {
  const ava = await signIn("seed-ava", password);
  clients.push(ava);
  const ben = await signIn("seed-ben", password);
  clients.push(ben);
  const avaBefore = (await pendingChances(ava)).length;
  const names = [ava.id, ben.id, "Ava", "Ben"];

  const a = await json(
    await post("discovery/start", {}, ava.credential),
    "Ava start failed",
  );
  leases.push([ava, a]);
  const b = await json(
    await post("discovery/start", {}, ben.credential),
    "Ben start failed",
  );
  leases.push([ben, b]);

  const observationId = randomUUID();
  const oneSided = await observe(ava, a, b, observationId);
  const oneSidedBody = await oneSided.text();
  check(oneSided.status === 200, "First observation failed");
  check(JSON.parse(oneSidedBody).status === "pending", "One-sided match");
  assertAnonymous(oneSidedBody, names);
  check(
    (await pendingChances(ava)).length === avaBefore,
    "A one-sided report opened a chance",
  );

  const reciprocal = await observe(ben, b, a);
  const reciprocalBody = await reciprocal.text();
  check(reciprocal.status === 200, "Reciprocal observation failed");
  check(
    JSON.parse(reciprocalBody).status === "recorded",
    "Reciprocal reports were not recorded",
  );
  assertAnonymous(reciprocalBody, names);
  const avaChances = await pendingChances(ava);
  const benChances = await pendingChances(ben);
  check(avaChances.length === avaBefore + 1, "No pending chance for Ava");
  const chance = avaChances[0];
  check(
    benChances.some((row) => row.id === chance.id),
    "Ben did not get the same chance",
  );
  check(chance.them === null, "A pending chance named the other person");

  const retry = await json(
    await observe(ava, a, b, observationId),
    "Retry failed",
  );
  check(retry.status === "recorded", "Retry did not see the match");

  const rotated = await json(
    await post("discovery/rotate", { sessionId: a.sessionId }, ava.credential),
    "Rotation failed",
  );
  check(
    rotated.token !== a.token && rotated.sessionId === a.sessionId,
    "Rotation contract mismatch",
  );
  await json(await observe(ben, b, rotated), "Rotated-token report failed");
  check(
    (await pendingChances(ava)).length === avaBefore + 1,
    "Rotation opened a second chance",
  );

  await json(
    await post("discovery/stop", { sessionId: a.sessionId }, ava.credential),
    "Stop failed",
  );
  const revoked = await observe(ben, b, rotated);
  check(revoked.status === 410, "A revoked token was accepted");

  const signedOut = await post("auth/sign-out", {}, ben.credential);
  check(signedOut.status === 200, "Ben sign-out failed");
  const afterSignOut = await post(
    "discovery/rotate",
    { sessionId: b.sessionId },
    ben.credential,
  );
  check(afterSignOut.status === 401, "A signed-out credential still worked");

  console.log(
    "PASS: real HTTP auth, anonymous receipts, one pending chance per reciprocal pair, retry, rotation, and revocation.",
  );
  console.log(
    "These were synthetic API reports. No Bluetooth or physical proximity was tested.",
  );
} finally {
  for (const [client, lease] of leases) {
    await post(
      "discovery/stop",
      { sessionId: lease.sessionId },
      client.credential,
    ).catch(() => {});
  }
  for (const client of clients) {
    await post("auth/sign-out", {}, client.credential).catch(() => {});
  }
}
