ALTER TABLE `interest` ADD `created_by` text REFERENCES user(id) ON DELETE set null;--> statement-breakpoint
ALTER TABLE `interest` ADD `created_at` integer;--> statement-breakpoint
CREATE INDEX `interest_created_by_idx` ON `interest` (`created_by`,`created_at`);--> statement-breakpoint
CREATE TRIGGER `interest_forum_open` AFTER UPDATE OF `member_count` ON `interest`
WHEN NEW.`member_count` >= 3
BEGIN
	INSERT OR IGNORE INTO `forum` (`id`, `interest_id`, `created_at`)
	VALUES (NEW.`id`, NEW.`id`, CAST(strftime('%s', 'now') AS INTEGER) * 1000);
END;
