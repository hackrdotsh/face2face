CREATE TABLE `forum` (
	`id` text PRIMARY KEY NOT NULL,
	`interest_id` text NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`interest_id`) REFERENCES `interest`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `forum_interest_id_unique` ON `forum` (`interest_id`);--> statement-breakpoint
CREATE TABLE `post` (
	`id` text PRIMARY KEY NOT NULL,
	`forum_id` text NOT NULL,
	`author_id` text NOT NULL,
	`title` text NOT NULL,
	`description` text,
	`location` text,
	`starts_at` integer NOT NULL,
	`ends_at` integer,
	`attendee_count` integer DEFAULT 0 NOT NULL,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL,
	`deleted_at` integer,
	FOREIGN KEY (`forum_id`) REFERENCES `forum`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`author_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade,
	CONSTRAINT "post_title_length" CHECK(length("post"."title") BETWEEN 1 AND 120),
	CONSTRAINT "post_description_length" CHECK("post"."description" IS NULL OR length("post"."description") BETWEEN 1 AND 4000),
	CONSTRAINT "post_location_length" CHECK("post"."location" IS NULL OR length("post"."location") BETWEEN 1 AND 200),
	CONSTRAINT "post_ends_after_start" CHECK("post"."ends_at" IS NULL OR "post"."ends_at" >= "post"."starts_at"),
	CONSTRAINT "post_attendee_count_not_negative" CHECK("post"."attendee_count" >= 0)
);
--> statement-breakpoint
CREATE INDEX `post_forum_feed_idx` ON `post` (`forum_id`,`created_at`) WHERE "post"."deleted_at" IS NULL;--> statement-breakpoint
CREATE INDEX `post_forum_upcoming_idx` ON `post` (`forum_id`,`starts_at`) WHERE "post"."deleted_at" IS NULL;--> statement-breakpoint
CREATE INDEX `post_author_id_idx` ON `post` (`author_id`);--> statement-breakpoint
CREATE TABLE `post_attendee` (
	`post_id` text NOT NULL,
	`user_id` text NOT NULL,
	`created_at` integer NOT NULL,
	PRIMARY KEY(`post_id`, `user_id`),
	FOREIGN KEY (`post_id`) REFERENCES `post`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `post_attendee_user_id_idx` ON `post_attendee` (`user_id`);