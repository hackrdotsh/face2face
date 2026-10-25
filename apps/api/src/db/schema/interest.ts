import { sql } from "drizzle-orm";
import {
  check,
  index,
  integer,
  primaryKey,
  sqliteTable,
  text,
} from "drizzle-orm/sqlite-core";
import { user } from "./auth";

export const interest = sqliteTable(
  "interest",
  {
    id: text("id").primaryKey(),
    name: text("name").notNull().unique(),
    memberCount: integer("member_count").notNull().default(0),
    /** Null for seeded interests. */
    createdBy: text("created_by").references(() => user.id, {
      onDelete: "set null",
    }),
    createdAt: integer("created_at", { mode: "timestamp_ms" }),
  },
  (table) => [
    check("interest_name_lowercase", sql`${table.name} = lower(${table.name})`),
    check("interest_member_count_not_negative", sql`${table.memberCount} >= 0`),
    index("interest_created_by_idx").on(table.createdBy, table.createdAt),
  ],
);

export const profileInterest = sqliteTable(
  "profile_interest",
  {
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    interestId: text("interest_id")
      .notNull()
      .references(() => interest.id),
    createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
  },
  (table) => [
    primaryKey({ columns: [table.userId, table.interestId] }),
    index("profile_interest_interest_id_idx").on(table.interestId),
  ],
);
