import { randomUUID } from "node:crypto";

const address = new URL(process.argv[2] ?? "http://127.0.0.1:8787");
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
    "Use a loopback API base URL. This test creates two local throwaway accounts.",
  );
}
const base = address.origin;
function check(condition, message) {
  if (!condition) throw new Error(message);
}
async function post(path, value, credential) {
  return fetch(base + "/api/" + path, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Origin: "face2face://",
      ...(credential ? { Authorization: "Bearer " + credential } : {}),
    },
    body: JSON.stringify(value),
    signal: AbortSignal.timeout(10_000),
  });
}
async function json(response, message) {
  check(response.status === 200, message + " (HTTP " + response.status + ")");
  return response.json();
}
async function account(name) {
  const response = await post("auth/sign-up/email", {
    name,
    email: randomUUID() + "@streetpass-smoke.test",
    password: randomUUID() + randomUUID(),
  });
  const credential = response.headers.get("set-auth-token");
  const payload = await json(response, "Could not create a local test account");
  check(credential && payload.user?.id, "Missing signed account credential");
  return { credential, id: payload.user.id };
}
async function history(client) {
  const response = await fetch(base + "/api/encounters", {
    headers: { Authorization: "Bearer " + client.credential },
    signal: AbortSignal.timeout(10_000),
  });
  return (await json(response, "History request failed")).encounters;
}

const clients = [];
const leases = [];
try {
  const alice = await account("Local smoke Alice");
  clients.push(alice);
  const bob = await account("Local smoke Bob");
  clients.push(bob);
  const a = await json(
    await post("discovery/start", {}, alice.credential),
    "Alice start failed",
  );
  leases.push([alice, a]);
  const b = await json(
    await post("discovery/start", {}, bob.credential),
    "Bob start failed",
  );
  leases.push([bob, b]);
  const observationId = randomUUID();
  const observeA = {
    sessionId: a.sessionId,
    peerToken: b.token,
    observationId,
  };
  const oneSided = await json(
    await post("encounters/observe", observeA, alice.credential),
    "First observation failed",
  );
  check(
    oneSided.status === "pending" && oneSided.encounter === null,
    "One-sided identity was disclosed",
  );
  check((await history(alice)).length === 0, "Unexpected one-sided history");

  const reciprocal = await json(
    await post(
      "encounters/observe",
      {
        sessionId: b.sessionId,
        peerToken: a.token,
        observationId: randomUUID(),
      },
      bob.credential,
    ),
    "Reciprocal observation failed",
  );
  check(
    reciprocal.status === "recorded",
    "Reciprocal encounter was not created",
  );
  const before = await history(alice);
  check(
    before.length === 1 && before[0].peer.id === bob.id,
    "Incorrect peer or duplicate encounter",
  );
  check(
    before[0].source === "client_reported_bluetooth",
    "Incorrect observation source",
  );
  const retry = await json(
    await post("encounters/observe", observeA, alice.credential),
    "Retry failed",
  );
  check(
    retry.encounter?.id === before[0].id,
    "Retry created a different encounter",
  );

  const rotated = await json(
    await post(
      "discovery/rotate",
      { sessionId: a.sessionId },
      alice.credential,
    ),
    "Rotation failed",
  );
  check(
    rotated.token !== a.token && rotated.sessionId === a.sessionId,
    "Rotation contract mismatch",
  );
  const afterRotation = await json(
    await post(
      "encounters/observe",
      {
        sessionId: b.sessionId,
        peerToken: rotated.token,
        observationId: randomUUID(),
      },
      bob.credential,
    ),
    "Rotated-token observation failed",
  );
  check(
    afterRotation.encounter?.id === before[0].id,
    "Rotation duplicated the encounter",
  );

  await json(
    await post("discovery/stop", { sessionId: a.sessionId }, alice.credential),
    "Stop failed",
  );
  const revoked = await post(
    "encounters/observe",
    {
      sessionId: b.sessionId,
      peerToken: rotated.token,
      observationId: randomUUID(),
    },
    bob.credential,
  );
  check(revoked.status === 410, "A revoked token was accepted");

  // Rehearse a second walk with the same accounts. The previous encounter remains
  // in history, but cannot become a fresh reciprocal record after just one report.
  const previousHistory = await history(alice);
  check(
    previousHistory.length === 1,
    "Stop unexpectedly removed encounter history",
  );
  const previous = previousHistory[0];
  const nextA = await json(
    await post("discovery/start", {}, alice.credential),
    "Second Alice start failed",
  );
  leases.push([alice, nextA]);
  const nextB = await json(
    await post("discovery/start", {}, bob.credential),
    "Second Bob start failed",
  );
  leases.push([bob, nextB]);
  check(
    nextA.sessionId !== a.sessionId && nextB.sessionId !== b.sessionId,
    "Restart reused a previous discovery session",
  );
  const secondObservation = {
    sessionId: nextA.sessionId,
    peerToken: nextB.token,
    observationId: randomUUID(),
  };
  const oldReceipt = await json(
    await post("encounters/observe", secondObservation, alice.credential),
    "Second-walk first observation failed",
  );
  check(
    oldReceipt.encounter?.id === previous.id &&
      oldReceipt.encounter.lastSeenAt === previous.lastSeenAt,
    "One-sided restart changed the old encounter",
  );
  const stillOld = await history(alice);
  check(
    stillOld.length === 1 && stillOld[0].lastSeenAt === previous.lastSeenAt,
    "Old reciprocal reports authorized a fresh second-walk encounter",
  );
  await json(
    await post(
      "encounters/observe",
      {
        sessionId: nextB.sessionId,
        peerToken: nextA.token,
        observationId: randomUUID(),
      },
      bob.credential,
    ),
    "Second-walk reciprocal observation failed",
  );
  const updated = await history(alice);
  check(
    updated.length === 1 &&
      updated[0].id === previous.id &&
      updated[0].lastSeenAt > previous.lastSeenAt &&
      updated[0].lastSeenAt >= Math.max(nextA.serverTime, nextB.serverTime),
    "Second walk did not refresh the existing pair after new reciprocal reports",
  );
  const duplicate = await json(
    await post("encounters/observe", secondObservation, alice.credential),
    "Second-walk retry failed",
  );
  check(
    duplicate.encounter?.lastSeenAt === updated[0].lastSeenAt,
    "Retry advanced the encounter timestamp",
  );
  const signedOut = await post("auth/sign-out", {}, alice.credential);
  check(signedOut.status === 200, "Alice sign-out failed");
  const signedOutToken = await post(
    "encounters/observe",
    {
      sessionId: nextB.sessionId,
      peerToken: nextA.token,
      observationId: randomUUID(),
    },
    bob.credential,
  );
  check(
    signedOutToken.status === 410,
    "Sign-out left a discovery token active",
  );
  console.log(
    "PASS: real HTTP auth, one-sided privacy, reciprocity, retry, rotation, and revocation.",
  );
  console.log(
    "PASS: second-walk history baseline, fresh reciprocity, stable retry timestamps, and sign-out revocation.",
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
