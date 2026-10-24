import { type Context, Hono, type MiddlewareHandler } from "hono";
import { HTTPException } from "hono/http-exception";
import { createAuth } from "./auth";

type DiscoveryEnv = {
  Bindings: Env;
  Variables: {
    userId: string;
    authSessionId: string;
    authExpiresAt: number;
    database: D1DatabaseSession;
  };
};
type Database = Pick<D1Database, "prepare" | "batch">;
type DiscoveryContext = Context<DiscoveryEnv>;
type LeaseRow = { id: string; user_id: string; expires_at: number };
type ObservationRow = { peer_token_hash: string; peer_user_id: string };
type EncounterRow = {
  id: string;
  first_seen_at: number;
  last_seen_at: number;
  peer_id: string;
  peer_name: string;
};

export const discoveryPolicy = {
  tokenTTL: 5 * 60_000,
  sessionTTL: 30 * 60_000,
  reciprocalWindow: 2 * 60_000,
  historyTTL: 24 * 60 * 60_000,
};
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function fail(status: 400 | 401 | 409 | 410 | 429, error: string): never {
  throw new HTTPException(status, {
    res: Response.json(
      { error },
      { status, headers: status === 429 ? { "Retry-After": "60" } : undefined },
    ),
  });
}

async function body(c: DiscoveryContext, keys: string[]) {
  let value: unknown;
  try {
    value = await c.req.json();
  } catch {
    fail(400, "invalid_json");
  }
  if (!value || typeof value !== "object" || Array.isArray(value))
    fail(400, "invalid_request");
  const result = value as Record<string, unknown>;
  if (Object.keys(result).some((key) => !keys.includes(key)))
    fail(400, "invalid_request");
  return result;
}

function uuid(value: unknown): string {
  if (typeof value !== "string" || !uuidPattern.test(value))
    fail(400, "invalid_identifier");
  return value.toLowerCase();
}

async function hash(value: string) {
  const data = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(data), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}

const authenticate: MiddlewareHandler<DiscoveryEnv> = async (c, next) => {
  const signedIn = await createAuth(c.env).api.getSession({
    headers: c.req.raw.headers,
  });
  if (!signedIn) fail(401, "unauthorized");
  c.set("userId", signedIn.user.id);
  c.set("authSessionId", signedIn.session.id);
  c.set("authExpiresAt", signedIn.session.expiresAt.getTime());
  // Keep reads after writes consistent even if D1 read replication is enabled later.
  c.set("database", c.env.DB.withSession("first-primary"));
  await next();
};

async function quota(
  c: DiscoveryContext,
  action: string,
  limit: number,
  now: number,
) {
  const row = await c
    .get("database")
    .prepare(
      "INSERT INTO discovery_quota (user_id, action, minute, count) VALUES (?, ?, ?, 1) " +
        "ON CONFLICT (user_id, action, minute) DO UPDATE SET count = count + 1 RETURNING count",
    )
    .bind(c.get("userId"), action, Math.floor(now / 60_000))
    .first<{ count: number }>();
  if (!row || row.count > limit) {
    c.header("Retry-After", "60");
    fail(429, "discovery_rate_limited");
  }
}

async function cleanup(db: Database, now: number) {
  // Bounded opportunistic cleanup; no cron job or external resource is provisioned.
  await db.batch([
    db
      .prepare(
        "DELETE FROM discovery_session WHERE id IN (SELECT id FROM discovery_session WHERE expires_at <= ? LIMIT 20)",
      )
      .bind(now),
    db
      .prepare(
        "DELETE FROM discovery_token WHERE hash IN (SELECT hash FROM discovery_token WHERE expires_at <= ? LIMIT 200)",
      )
      .bind(now),
    db
      .prepare(
        "DELETE FROM discovery_observation WHERE id IN (SELECT id FROM discovery_observation WHERE received_at < ? LIMIT 200)",
      )
      .bind(now - discoveryPolicy.sessionTTL),
    db
      .prepare(
        "DELETE FROM encounter WHERE id IN (SELECT id FROM encounter WHERE last_seen_at < ? LIMIT 100)",
      )
      .bind(now - discoveryPolicy.historyTTL),
    db
      .prepare(
        "DELETE FROM discovery_quota WHERE rowid IN (SELECT rowid FROM discovery_quota WHERE minute < ? LIMIT 100)",
      )
      .bind(Math.floor(now / 60_000) - 2),
  ]);
}

async function activeLease(
  c: DiscoveryContext,
  sessionId: string,
  now: number,
) {
  const lease = await c
    .get("database")
    .prepare(
      "SELECT id, user_id, expires_at FROM discovery_session " +
        "WHERE id = ? AND user_id = ? AND auth_session_id = ? AND expires_at > ?",
    )
    .bind(sessionId, c.get("userId"), c.get("authSessionId"), now)
    .first<LeaseRow>();
  if (!lease) fail(410, "discovery_inactive");
  return lease;
}

function encodeEncounter(row: EncounterRow) {
  return {
    id: row.id,
    peer: { id: row.peer_id, name: row.peer_name },
    firstSeenAt: row.first_seen_at,
    lastSeenAt: row.last_seen_at,
    source: "client_reported_bluetooth" as const,
  };
}

async function receipt(c: DiscoveryContext, peerUserId: string, now: number) {
  const userId = c.get("userId");
  const [low, high] = [userId, peerUserId].sort();
  const row = await c
    .get("database")
    .prepare(
      "SELECT e.id, e.first_seen_at, e.last_seen_at, u.id AS peer_id, u.name AS peer_name " +
        "FROM encounter e JOIN user u ON u.id = ? " +
        "WHERE e.user_low_id = ? AND e.user_high_id = ? AND e.last_seen_at >= ?",
    )
    .bind(peerUserId, low, high, now - discoveryPolicy.historyTTL)
    .first<EncounterRow>();
  return c.json({
    status: row ? ("recorded" as const) : ("pending" as const),
    encounter: row ? encodeEncounter(row) : null,
  });
}

export const discoveryRoutes = new Hono<DiscoveryEnv>();
discoveryRoutes.use("/discovery/*", authenticate);
discoveryRoutes.use("/encounters", authenticate);
discoveryRoutes.use("/encounters/*", authenticate);

discoveryRoutes.post("/discovery/start", async (c) => {
  await body(c, []);
  const now = Date.now();
  await quota(c, "start", 10, now);
  const db = c.get("database");
  await cleanup(db, now);
  const sessionId = crypto.randomUUID();
  const token = crypto.randomUUID();
  const expiresAt = Math.min(
    now + discoveryPolicy.sessionTTL,
    c.get("authExpiresAt"),
  );
  const tokenExpiresAt = Math.min(now + discoveryPolicy.tokenTTL, expiresAt);
  const tokenHash = await hash(token);
  await db.batch([
    // One opted-in session per account. Starting replaces and revokes its previous session.
    db
      .prepare("DELETE FROM discovery_session WHERE user_id = ?")
      .bind(c.get("userId")),
    db
      .prepare(
        "INSERT INTO discovery_session (id, user_id, auth_session_id, created_at, expires_at) " +
          "SELECT ?, ?, ?, ?, ? FROM session WHERE id = ? AND user_id = ? AND expires_at > ?",
      )
      .bind(
        sessionId,
        c.get("userId"),
        c.get("authSessionId"),
        now,
        expiresAt,
        c.get("authSessionId"),
        c.get("userId"),
        now,
      ),
    db
      .prepare(
        "INSERT INTO discovery_token (hash, session_id, expires_at) " +
          "SELECT ?, id, ? FROM discovery_session WHERE id = ?",
      )
      .bind(tokenHash, tokenExpiresAt, sessionId),
  ]);
  await activeLease(c, sessionId, now);
  return c.json({
    sessionId,
    token,
    expiresAt: tokenExpiresAt,
    sessionExpiresAt: expiresAt,
    serverTime: now,
  });
});

discoveryRoutes.post("/discovery/rotate", async (c) => {
  const request = await body(c, ["sessionId"]);
  const sessionId = uuid(request.sessionId);
  const now = Date.now();
  const lease = await activeLease(c, sessionId, now);
  await quota(c, "rotate", 12, now);
  const token = crypto.randomUUID();
  const expiresAt = Math.min(now + discoveryPolicy.tokenTTL, lease.expires_at);
  const result = await c
    .get("database")
    .prepare(
      "INSERT INTO discovery_token (hash, session_id, expires_at) " +
        "SELECT ?, id, ? FROM discovery_session WHERE id = ? AND user_id = ? AND auth_session_id = ? AND expires_at > ?",
    )
    .bind(
      await hash(token),
      expiresAt,
      sessionId,
      c.get("userId"),
      c.get("authSessionId"),
      now,
    )
    .run();
  if (result.meta.changes !== 1) fail(410, "discovery_inactive");
  // Existing tokens overlap until their original expiry so in-flight handshakes can finish.
  return c.json({
    sessionId,
    token,
    expiresAt,
    sessionExpiresAt: lease.expires_at,
    serverTime: now,
  });
});

discoveryRoutes.post("/discovery/stop", async (c) => {
  const request = await body(c, ["sessionId"]);
  const sessionId = uuid(request.sessionId);
  await c
    .get("database")
    .prepare(
      "DELETE FROM discovery_session WHERE id = ? AND user_id = ? AND auth_session_id = ?",
    )
    .bind(sessionId, c.get("userId"), c.get("authSessionId"))
    .run();
  // Idempotent and deliberately does not reveal whether another person's session exists.
  return c.json({ stopped: true });
});

discoveryRoutes.post("/encounters/observe", async (c) => {
  const request = await body(c, ["sessionId", "peerToken", "observationId"]);
  const sessionId = uuid(request.sessionId);
  const peerToken = uuid(request.peerToken);
  const observationId = uuid(request.observationId);
  const now = Date.now();
  await activeLease(c, sessionId, now);
  const db = c.get("database");
  const tokenHash = await hash(peerToken);
  const id = await hash(sessionId + ":" + observationId);
  const previous = await db
    .prepare(
      "SELECT peer_token_hash, peer_user_id FROM discovery_observation WHERE id = ? AND observer_session_id = ?",
    )
    .bind(id, sessionId)
    .first<ObservationRow>();
  if (previous) {
    if (previous.peer_token_hash !== tokenHash)
      fail(409, "observation_conflict");
    return receipt(c, previous.peer_user_id, now);
  }
  await quota(c, "observe", 120, now);
  const peer = await db
    .prepare(
      "SELECT s.id, s.user_id, s.expires_at FROM discovery_token t " +
        "JOIN discovery_session s ON s.id = t.session_id " +
        "WHERE t.hash = ? AND t.expires_at > ? AND s.expires_at > ?",
    )
    .bind(tokenHash, now, now)
    .first<LeaseRow>();
  if (!peer) fail(410, "invalid_peer_token");
  if (peer.user_id === c.get("userId")) fail(400, "self_encounter");
  const [low, high] = [c.get("userId"), peer.user_id].sort();
  await db.batch([
    // Liveness is rechecked inside the transaction to handle concurrent Stop/restart.
    db
      .prepare(
        "INSERT INTO discovery_observation " +
          "(id, observer_session_id, peer_session_id, peer_user_id, peer_token_hash, received_at) " +
          "SELECT ?, own.id, peer.id, peer.user_id, t.hash, ? " +
          "FROM discovery_session own JOIN discovery_session peer ON peer.id = ? " +
          "JOIN discovery_token t ON t.session_id = peer.id AND t.hash = ? " +
          "WHERE own.id = ? AND own.user_id = ? AND own.auth_session_id = ? " +
          "AND own.expires_at > ? AND peer.expires_at > ? AND t.expires_at > ? " +
          "ON CONFLICT(id) DO NOTHING",
      )
      .bind(
        id,
        now,
        peer.id,
        tokenHash,
        sessionId,
        c.get("userId"),
        c.get("authSessionId"),
        now,
        now,
        now,
      ),
    // Reciprocal observations must refer to the same two active sessions, within two minutes.
    db
      .prepare(
        "INSERT INTO encounter (id, user_low_id, user_high_id, first_seen_at, last_seen_at) " +
          "SELECT ?, ?, ?, ?, ? WHERE EXISTS (" +
          "SELECT 1 FROM discovery_observation mine JOIN discovery_observation theirs " +
          "ON theirs.observer_session_id = mine.peer_session_id AND theirs.peer_session_id = mine.observer_session_id " +
          "JOIN discovery_session own ON own.id = mine.observer_session_id " +
          "JOIN discovery_session peer ON peer.id = mine.peer_session_id " +
          "WHERE mine.id = ? AND mine.peer_token_hash = ? AND mine.peer_session_id = ? " +
          "AND theirs.received_at >= ? AND own.expires_at > ? AND peer.expires_at > ?) " +
          "ON CONFLICT(user_low_id, user_high_id) DO UPDATE SET last_seen_at = max(encounter.last_seen_at, excluded.last_seen_at)",
      )
      .bind(
        crypto.randomUUID(),
        low,
        high,
        now,
        now,
        id,
        tokenHash,
        peer.id,
        now - discoveryPolicy.reciprocalWindow,
        now,
        now,
      ),
  ]);
  const accepted = await db
    .prepare(
      "SELECT peer_token_hash, peer_user_id FROM discovery_observation WHERE id = ? AND observer_session_id = ?",
    )
    .bind(id, sessionId)
    .first<ObservationRow>();
  if (!accepted) fail(410, "discovery_inactive");
  if (accepted.peer_token_hash !== tokenHash) fail(409, "observation_conflict");
  return receipt(c, accepted.peer_user_id, now);
});

discoveryRoutes.get("/encounters", async (c) => {
  const db = c.get("database");
  const now = Date.now();
  await cleanup(db, now);
  const userId = c.get("userId");
  const rows = await db
    .prepare(
      "SELECT e.id, e.first_seen_at, e.last_seen_at, u.id AS peer_id, u.name AS peer_name " +
        "FROM encounter e JOIN user u ON u.id = CASE WHEN e.user_low_id = ? THEN e.user_high_id ELSE e.user_low_id END " +
        "WHERE (e.user_low_id = ? OR e.user_high_id = ?) AND e.last_seen_at >= ? " +
        "ORDER BY e.last_seen_at DESC, e.id DESC LIMIT 50",
    )
    .bind(userId, userId, userId, now - discoveryPolicy.historyTTL)
    .all<EncounterRow>();
  return c.json({ encounters: rows.results.map(encodeEncounter) });
});
