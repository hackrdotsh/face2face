CREATE TRIGGER `post_attendee_count_insert` AFTER INSERT ON `post_attendee`
BEGIN
	UPDATE `post` SET `attendee_count` = `attendee_count` + 1 WHERE `id` = NEW.`post_id`;
END;
--> statement-breakpoint
CREATE TRIGGER `post_attendee_count_delete` AFTER DELETE ON `post_attendee`
BEGIN
	UPDATE `post` SET `attendee_count` = `attendee_count` - 1 WHERE `id` = OLD.`post_id`;
END;
