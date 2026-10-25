CREATE TRIGGER `profile_interest_count_insert` AFTER INSERT ON `profile_interest`
BEGIN
	UPDATE `interest` SET `member_count` = `member_count` + 1 WHERE `id` = NEW.`interest_id`;
END;
--> statement-breakpoint
CREATE TRIGGER `profile_interest_count_delete` AFTER DELETE ON `profile_interest`
BEGIN
	UPDATE `interest` SET `member_count` = `member_count` - 1 WHERE `id` = OLD.`interest_id`;
END;
