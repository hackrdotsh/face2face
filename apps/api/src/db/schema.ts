import {
  index,
  integer,
  primaryKey,
  sqliteTable,
  text,
  uniqueIndex,
} from "drizzle-orm/sqlite-core";

export const rateLimit = sqliteTable("rate_limit", {
  id: text("id").primaryKey(),
  key: text("key").notNull().unique(),
  count: integer("count").notNull(),
  lastRequest: integer("last_request").notNull(),
});

export const user = sqliteTable("user", {
  id: text("id").primaryKey(),
  name: text("name").notNull(),
  email: text("email").notNull().unique(),
  emailVerified: integer("email_verified", { mode: "boolean" })
    .notNull()
    .default(false),
  image: text("image"),
  createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
  updatedAt: integer("updated_at", { mode: "timestamp_ms" }).notNull(),
});

export const session = sqliteTable(
  "session",
  {
    id: text("id").primaryKey(),
    expiresAt: integer("expires_at", { mode: "timestamp_ms" }).notNull(),
    token: text("token").notNull().unique(),
    createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
    updatedAt: integer("updated_at", { mode: "timestamp_ms" }).notNull(),
    ipAddress: text("ip_address"),
    userAgent: text("user_agent"),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
  },
  (table) => [index("session_user_id_idx").on(table.userId)],
);

export const account = sqliteTable(
  "account",
  {
    id: text("id").primaryKey(),
    accountId: text("account_id").notNull(),
    providerId: text("provider_id").notNull(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    accessToken: text("access_token"),
    refreshToken: text("refresh_token"),
    idToken: text("id_token"),
    accessTokenExpiresAt: integer("access_token_expires_at", {
      mode: "timestamp_ms",
    }),
    refreshTokenExpiresAt: integer("refresh_token_expires_at", {
      mode: "timestamp_ms",
    }),
    scope: text("scope"),
    password: text("password"),
    createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
    updatedAt: integer("updated_at", { mode: "timestamp_ms" }).notNull(),
  },
  (table) => [index("account_user_id_idx").on(table.userId)],
);

export const verification = sqliteTable(
  "verification",
  {
    id: text("id").primaryKey(),
    identifier: text("identifier").notNull(),
    value: text("value").notNull(),
    expiresAt: integer("expires_at", { mode: "timestamp_ms" }).notNull(),
    createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
    updatedAt: integer("updated_at", { mode: "timestamp_ms" }).notNull(),
  },
  (table) => [index("verification_identifier_idx").on(table.identifier)],
);

// Discovery tokens are opaque radio locators. Only their hashes are stored here.
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
    createdAt: integer("created_at").notNull(),
    expiresAt: integer("expires_at").notNull(),
  },
  (table) => [
    uniqueIndex("discovery_session_user_idx").on(table.userId),
    index("discovery_session_auth_idx").on(table.authSessionId),
    index("discovery_session_expiry_idx").on(table.expiresAt),
  ],
);

export const discoveryToken = sqliteTable(
  "discovery_token",
  {
    hash: text("hash").primaryKey(),
    sessionId: text("session_id")
      .notNull()
      .references(() => discoverySession.id, { onDelete: "cascade" }),
    expiresAt: integer("expires_at").notNull(),
  },
  (table) => [
    index("discovery_token_session_idx").on(table.sessionId),
    index("discovery_token_expiry_idx").on(table.expiresAt),
  ],
);

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
    receivedAt: integer("received_at").notNull(),
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

export const encounter = sqliteTable(
  "encounter",
  {
    id: text("id").primaryKey(),
    userLowId: text("user_low_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    userHighId: text("user_high_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    firstSeenAt: integer("first_seen_at").notNull(),
    lastSeenAt: integer("last_seen_at").notNull(),
  },
  (table) => [
    uniqueIndex("encounter_pair_idx").on(table.userLowId, table.userHighId),
    index("encounter_low_idx").on(table.userLowId, table.lastSeenAt),
    index("encounter_high_idx").on(table.userHighId, table.lastSeenAt),
    index("encounter_expiry_idx").on(table.lastSeenAt),
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
