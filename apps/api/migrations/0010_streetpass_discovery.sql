CREATE TABLE `discovery_observation` (
	`id` text PRIMARY KEY NOT NULL,
	`observer_session_id` text NOT NULL,
	`peer_session_id` text NOT NULL,
	`peer_user_id` text NOT NULL,
	`peer_token_hash` text NOT NULL,
	`received_at` integer NOT NULL,
	`matched_at` integer,
	FOREIGN KEY (`observer_session_id`) REFERENCES `discovery_session`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`peer_session_id`) REFERENCES `discovery_session`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`peer_user_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `discovery_observation_pair_idx` ON `discovery_observation` (`observer_session_id`,`peer_session_id`,`received_at`);--> statement-breakpoint
CREATE INDEX `discovery_observation_peer_idx` ON `discovery_observation` (`peer_session_id`);--> statement-breakpoint
CREATE INDEX `discovery_observation_user_idx` ON `discovery_observation` (`peer_user_id`);--> statement-breakpoint
CREATE INDEX `discovery_observation_expiry_idx` ON `discovery_observation` (`received_at`);--> statement-breakpoint
CREATE TABLE `discovery_quota` (
	`user_id` text NOT NULL,
	`action` text NOT NULL,
	`minute` integer NOT NULL,
	`count` integer NOT NULL,
	PRIMARY KEY(`user_id`, `action`, `minute`),
	FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `discovery_quota_expiry_idx` ON `discovery_quota` (`minute`);--> statement-breakpoint
CREATE TABLE `discovery_session` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`auth_session_id` text NOT NULL,
	`created_at` integer NOT NULL,
	`expires_at` integer NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`auth_session_id`) REFERENCES `session`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `discovery_session_user_idx` ON `discovery_session` (`user_id`);--> statement-breakpoint
CREATE INDEX `discovery_session_auth_idx` ON `discovery_session` (`auth_session_id`);--> statement-breakpoint
CREATE INDEX `discovery_session_expiry_idx` ON `discovery_session` (`expires_at`);--> statement-breakpoint
CREATE TABLE `discovery_token` (
	`hash` text PRIMARY KEY NOT NULL,
	`session_id` text NOT NULL,
	`expires_at` integer NOT NULL,
	FOREIGN KEY (`session_id`) REFERENCES `discovery_session`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `discovery_token_session_idx` ON `discovery_token` (`session_id`);--> statement-breakpoint
CREATE INDEX `discovery_token_expiry_idx` ON `discovery_token` (`expires_at`);