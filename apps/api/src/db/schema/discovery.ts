import {
  index,
  integer,
  primaryKey,
  sqliteTable,
  text,
  uniqueIndex,
} from "drizzle-orm/sqlite-core";
import { session, user } from "./auth";

/** One opted-in discovery lease per account, bound to the auth session that started it. */
export const discoverySession = sqliteTable(
  "discovery_session",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    authSessionId: text("auth_session_id")
      .notNull()
      .references(() => session.id, { onDelete: "cascade" }),
    createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
    expiresAt: integer("expires_at", { mode: "timestamp_ms" }).notNull(),
  },
  (table) => [
    uniqueIndex("discovery_session_user_idx").on(table.userId),
    index("discovery_session_auth_idx").on(table.authSessionId),
    index("discovery_session_expiry_idx").on(table.expiresAt),
  ],
);

/** Radio tokens are opaque locators. Only their SHA-256 hashes are stored. */
export const discoveryToken = sqliteTable(
  "discovery_token",
  {
    hash: text("hash").primaryKey(),
    sessionId: text("session_id")
      .notNull()
      .references(() => discoverySession.id, { onDelete: "cascade" }),
    expiresAt: integer("expires_at", { mode: "timestamp_ms" }).notNull(),
  },
  (table) => [
    index("discovery_token_session_idx").on(table.sessionId),
    index("discovery_token_expiry_idx").on(table.expiresAt),
  ],
);

/** One phone's report that it heard another phone's token. */
export const discoveryObservation = sqliteTable(
  "discovery_observation",
  {
    id: text("id").primaryKey(),
    observerSessionId: text("observer_session_id")
      .notNull()
      .references(() => discoverySession.id, { onDelete: "cascade" }),
    peerSessionId: text("peer_session_id")
      .notNull()
      .references(() => discoverySession.id, { onDelete: "cascade" }),
    peerUserId: text("peer_user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    peerTokenHash: text("peer_token_hash").notNull(),
    receivedAt: integer("received_at", { mode: "timestamp_ms" }).notNull(),
    /** Set on both reports once they match and the encounter is recorded. */
    matchedAt: integer("matched_at", { mode: "timestamp_ms" }),
  },
  (table) => [
    index("discovery_observation_pair_idx").on(
      table.observerSessionId,
      table.peerSessionId,
      table.receivedAt,
    ),
    index("discovery_observation_peer_idx").on(table.peerSessionId),
    index("discovery_observation_user_idx").on(table.peerUserId),
    index("discovery_observation_expiry_idx").on(table.receivedAt),
  ],
);

export const discoveryQuota = sqliteTable(
  "discovery_quota",
  {
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    action: text("action").notNull(),
    minute: integer("minute").notNull(),
    count: integer("count").notNull(),
  },
  (table) => [
    primaryKey({ columns: [table.userId, table.action, table.minute] }),
    index("discovery_quota_expiry_idx").on(table.minute),
  ],
);
