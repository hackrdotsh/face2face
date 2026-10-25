import { sql } from "drizzle-orm";
import {
  check,
  index,
  integer,
  primaryKey,
  sqliteTable,
  text,
  uniqueIndex,
} from "drizzle-orm/sqlite-core";
import { user } from "./auth";

export const connectionStatuses = [
  "pending",
  "expired",
  "private",
  "public",
  "blocked",
] as const;
export const connectionDecisions = ["accepted", "declined"] as const;
export const connectionSides = ["low", "high"] as const;

export type ConnectionStatus = (typeof connectionStatuses)[number];
export type ConnectionDecision = (typeof connectionDecisions)[number];
export type ConnectionSide = (typeof connectionSides)[number];

export const connection = sqliteTable(
  "connection",
  {
    id: text("id").primaryKey(),
    userLowId: text("user_low_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    userHighId: text("user_high_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    status: text("status", { enum: connectionStatuses }).notNull(),
    /** Interest names both people had when they met. Written once. */
    sharedInterests: text("shared_interests", { mode: "json" })
      .$type<string[]>()
      .notNull(),
    lowDecision: text("low_decision", { enum: connectionDecisions }),
    lowDecidedAt: integer("low_decided_at", { mode: "timestamp_ms" }),
    highDecision: text("high_decision", { enum: connectionDecisions }),
    highDecidedAt: integer("high_decided_at", { mode: "timestamp_ms" }),
    lowPublicAt: integer("low_public_at", { mode: "timestamp_ms" }),
    highPublicAt: integer("high_public_at", { mode: "timestamp_ms" }),
    blockedBy: text("blocked_by", { enum: connectionSides }),
    createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
    expiresAt: integer("expires_at", { mode: "timestamp_ms" }).notNull(),
    resolvedAt: integer("resolved_at", { mode: "timestamp_ms" }),
  },
  (table) => [
    check(
      "connection_pair_ordered",
      sql`${table.userLowId} < ${table.userHighId}`,
    ),
    check(
      "connection_blocked_by_matches_status",
      sql`(${table.blockedBy} IS NOT NULL) = (${table.status} = 'blocked')`,
    ),
    check(
      "connection_public_needs_both_consents",
      sql`${table.status} <> 'public' OR (${table.lowPublicAt} IS NOT NULL AND ${table.highPublicAt} IS NOT NULL)`,
    ),
    check(
      "connection_open_needs_both_accepted",
      sql`${table.status} NOT IN ('private', 'public') OR (${table.lowDecision} = 'accepted' AND ${table.highDecision} = 'accepted')`,
    ),
    uniqueIndex("connection_open_pair_idx")
      .on(table.userLowId, table.userHighId)
      .where(sql`${table.status} = 'pending'`),
    index("connection_low_status_idx").on(table.userLowId, table.status),
    index("connection_high_status_idx").on(table.userHighId, table.status),
  ],
);

export const block = sqliteTable(
  "block",
  {
    blockerId: text("blocker_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    blockedId: text("blocked_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    connectionId: text("connection_id").references(() => connection.id, {
      onDelete: "set null",
    }),
    createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
  },
  (table) => [
    primaryKey({ columns: [table.blockerId, table.blockedId] }),
    index("block_blocked_id_idx").on(table.blockedId),
  ],
);
