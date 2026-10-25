import { index, integer, sqliteTable, text } from "drizzle-orm/sqlite-core";
import { user } from "./auth";

/**
 * Which account last registered each phone for push. Only the SHA-256 hash of
 * the APNs token is stored here; the token itself lives in the owner's
 * `UserCoordinator`. A phone has one owner, so a new sign-in moves it.
 */
export const pushDevice = sqliteTable(
  "push_device",
  {
    tokenHash: text("token_hash").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    updatedAt: integer("updated_at", { mode: "timestamp_ms" }).notNull(),
  },
  (table) => [index("push_device_user_idx").on(table.userId)],
);
