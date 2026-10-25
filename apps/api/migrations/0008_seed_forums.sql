INSERT INTO `forum` (`id`, `interest_id`, `created_at`)
SELECT `id`, `id`, CAST(strftime('%s', 'now') AS INTEGER) * 1000 FROM `interest`;
