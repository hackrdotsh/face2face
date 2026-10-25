CREATE TABLE `block` (
	`blocker_id` text NOT NULL,
	`blocked_id` text NOT NULL,
	`connection_id` text,
	`created_at` integer NOT NULL,
	PRIMARY KEY(`blocker_id`, `blocked_id`),
	FOREIGN KEY (`blocker_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`blocked_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`connection_id`) REFERENCES `connection`(`id`) ON UPDATE no action ON DELETE set null
);
--> statement-breakpoint
CREATE INDEX `block_blocked_id_idx` ON `block` (`blocked_id`);--> statement-breakpoint
CREATE TABLE `connection` (
	`id` text PRIMARY KEY NOT NULL,
	`user_low_id` text NOT NULL,
	`user_high_id` text NOT NULL,
	`status` text NOT NULL,
	`shared_interests` text NOT NULL,
	`low_decision` text,
	`low_decided_at` integer,
	`high_decision` text,
	`high_decided_at` integer,
	`low_public_at` integer,
	`high_public_at` integer,
	`blocked_by` text,
	`created_at` integer NOT NULL,
	`expires_at` integer NOT NULL,
	`resolved_at` integer,
	FOREIGN KEY (`user_low_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`user_high_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade,
	CONSTRAINT "connection_pair_ordered" CHECK("connection"."user_low_id" < "connection"."user_high_id"),
	CONSTRAINT "connection_blocked_by_matches_status" CHECK(("connection"."blocked_by" IS NOT NULL) = ("connection"."status" = 'blocked')),
	CONSTRAINT "connection_public_needs_both_consents" CHECK("connection"."status" <> 'public' OR ("connection"."low_public_at" IS NOT NULL AND "connection"."high_public_at" IS NOT NULL)),
	CONSTRAINT "connection_open_needs_both_accepted" CHECK("connection"."status" NOT IN ('private', 'public') OR ("connection"."low_decision" = 'accepted' AND "connection"."high_decision" = 'accepted'))
);
--> statement-breakpoint
CREATE UNIQUE INDEX `connection_open_pair_idx` ON `connection` (`user_low_id`,`user_high_id`) WHERE "connection"."status" = 'pending';--> statement-breakpoint
CREATE INDEX `connection_low_status_idx` ON `connection` (`user_low_id`,`status`);--> statement-breakpoint
CREATE INDEX `connection_high_status_idx` ON `connection` (`user_high_id`,`status`);--> statement-breakpoint
CREATE TABLE `interest` (
	`id` text PRIMARY KEY NOT NULL,
	`name` text NOT NULL,
	`member_count` integer DEFAULT 0 NOT NULL,
	CONSTRAINT "interest_name_lowercase" CHECK("interest"."name" = lower("interest"."name")),
	CONSTRAINT "interest_member_count_not_negative" CHECK("interest"."member_count" >= 0)
);
--> statement-breakpoint
CREATE UNIQUE INDEX `interest_name_unique` ON `interest` (`name`);--> statement-breakpoint
CREATE TABLE `profile_interest` (
	`user_id` text NOT NULL,
	`interest_id` text NOT NULL,
	`created_at` integer NOT NULL,
	PRIMARY KEY(`user_id`, `interest_id`),
	FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`interest_id`) REFERENCES `interest`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `profile_interest_interest_id_idx` ON `profile_interest` (`interest_id`);