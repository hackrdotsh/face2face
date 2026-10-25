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
import { interest } from "./interest";

export const postTitleMaxLength = 120;
export const postDescriptionMaxLength = 4000;
export const postLocationMaxLength = 200;

/** One per interest. Seeded with the interest list. */
export const forum = sqliteTable("forum", {
  id: text("id").primaryKey(),
  interestId: text("interest_id")
    .notNull()
    .unique()
    .references(() => interest.id),
  createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
});

/** An event in a forum. Deleting sets `deletedAt` and keeps the row. */
export const post = sqliteTable(
  "post",
  {
    id: text("id").primaryKey(),
    forumId: text("forum_id")
      .notNull()
      .references(() => forum.id),
    authorId: text("author_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    title: text("title").notNull(),
    description: text("description"),
    location: text("location"),
    startsAt: integer("starts_at", { mode: "timestamp_ms" }).notNull(),
    endsAt: integer("ends_at", { mode: "timestamp_ms" }),
    attendeeCount: integer("attendee_count").notNull().default(0),
    createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
    updatedAt: integer("updated_at", { mode: "timestamp_ms" }).notNull(),
    deletedAt: integer("deleted_at", { mode: "timestamp_ms" }),
  },
  (table) => [
    check(
      "post_title_length",
      sql`length(${table.title}) BETWEEN 1 AND ${sql.raw(String(postTitleMaxLength))}`,
    ),
    check(
      "post_description_length",
      sql`${table.description} IS NULL OR length(${table.description}) BETWEEN 1 AND ${sql.raw(String(postDescriptionMaxLength))}`,
    ),
    check(
      "post_location_length",
      sql`${table.location} IS NULL OR length(${table.location}) BETWEEN 1 AND ${sql.raw(String(postLocationMaxLength))}`,
    ),
    check(
      "post_ends_after_start",
      sql`${table.endsAt} IS NULL OR ${table.endsAt} >= ${table.startsAt}`,
    ),
    check("post_attendee_count_not_negative", sql`${table.attendeeCount} >= 0`),
    index("post_forum_feed_idx")
      .on(table.forumId, table.createdAt)
      .where(sql`${table.deletedAt} IS NULL`),
    index("post_forum_upcoming_idx")
      .on(table.forumId, table.startsAt)
      .where(sql`${table.deletedAt} IS NULL`),
    index("post_author_id_idx").on(table.authorId),
  ],
);

export const postAttendee = sqliteTable(
  "post_attendee",
  {
    postId: text("post_id")
      .notNull()
      .references(() => post.id, { onDelete: "cascade" }),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
  },
  (table) => [
    primaryKey({ columns: [table.postId, table.userId] }),
    index("post_attendee_user_id_idx").on(table.userId),
  ],
);
