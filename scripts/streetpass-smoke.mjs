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
const { users } = await json(
  await request("dev/users"),
  "Dev users request failed",
);
const { connections: rows } = await json(
  await request("dev/connections"),
  "Dev connections request failed",
);
const rowsFor = (first, second) =>
  rows.filter(
    (row) =>
      [row.userLowId, row.userHighId].includes(first.id) &&
      [row.userLowId, row.userHighId].includes(second.id),
  );
// A connected or blocked pair cannot get a new chance, so pick a pair without one.
const seeds = users.filter((user) => user.id.startsWith("seed-"));
const people = seeds
  .flatMap((first, index) =>
    seeds.slice(index + 1).map((second) => [first, second]),
  )
  .find(([first, second]) =>
    rowsFor(first, second).every((row) =>
      ["pending", "expired"].includes(row.status),
    ),
  );
check(people, "Every seed pair is connected. Run POST /api/dev/reset first.");
const [first, second] = people;
console.log(`Using ${first.id} and ${second.id}.`);
for (const row of rowsFor(first, second)) {
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
  const one = await signIn(first.id, password);
  clients.push(one);
  const two = await signIn(second.id, password);
  clients.push(two);
  const firstBefore = (await pendingChances(one)).length;
  const names = [first.id, second.id, first.name, second.name];

  const a = await json(
    await post("discovery/start", {}, one.credential),
    "First start failed",
  );
  leases.push([one, a]);
  const b = await json(
    await post("discovery/start", {}, two.credential),
    "Second start failed",
  );
  leases.push([two, b]);

  const observationId = randomUUID();
  const oneSided = await observe(one, a, b, observationId);
  const oneSidedBody = await oneSided.text();
  check(oneSided.status === 200, "First observation failed");
  check(JSON.parse(oneSidedBody).status === "pending", "One-sided match");
  assertAnonymous(oneSidedBody, names);
  check(
    (await pendingChances(one)).length === firstBefore,
    "A one-sided report opened a chance",
  );

  const reciprocal = await observe(two, b, a);
  const reciprocalBody = await reciprocal.text();
  check(reciprocal.status === 200, "Reciprocal observation failed");
  check(
    JSON.parse(reciprocalBody).status === "recorded",
    "Reciprocal reports were not recorded",
  );
  assertAnonymous(reciprocalBody, names);
  const firstChances = await pendingChances(one);
  const secondChances = await pendingChances(two);
  check(
    firstChances.length === firstBefore + 1,
    "No pending chance for the first person",
  );
  const chance = firstChances[0];
  check(
    secondChances.some((row) => row.id === chance.id),
    "The second person did not get the same chance",
  );
  check(chance.them === null, "A pending chance named the other person");

  const retry = await json(
    await observe(one, a, b, observationId),
    "Retry failed",
  );
  check(retry.status === "recorded", "Retry did not see the match");

  const rotated = await json(
    await post("discovery/rotate", { sessionId: a.sessionId }, one.credential),
    "Rotation failed",
  );
  check(
    rotated.token !== a.token && rotated.sessionId === a.sessionId,
    "Rotation contract mismatch",
  );
  await json(await observe(two, b, rotated), "Rotated-token report failed");
  check(
    (await pendingChances(one)).length === firstBefore + 1,
    "Rotation opened a second chance",
  );

  await json(
    await post("discovery/stop", { sessionId: a.sessionId }, one.credential),
    "Stop failed",
  );
  const revoked = await observe(two, b, rotated);
  check(revoked.status === 410, "A revoked token was accepted");

  const signedOut = await post("auth/sign-out", {}, two.credential);
  check(signedOut.status === 200, "Second sign-out failed");
  const afterSignOut = await post(
    "discovery/rotate",
    { sessionId: b.sessionId },
    two.credential,
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
