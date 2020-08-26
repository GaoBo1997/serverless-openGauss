\c upsert
SET CURRENT_SCHEMA TO upsert_test;
-- enable_upsert_to_merge must be off, or upsert will be translated to merge.
SET enable_upsert_to_merge TO OFF;
SHOW enable_upsert_to_merge;

-- support multiple set
INSERT INTO t_grammer VALUES(11, 1) ON DUPLICATE KEY UPDATE c2 = 2, c4 = ROW(10, 20), c3 = '{10, 20, 30}';
INSERT INTO t_grammer VALUES(12, 2) ON DUPLICATE KEY UPDATE c2 = 2, c3[1] = 3;

-- support const value and expr
INSERT INTO t_grammer VALUES(23) ON DUPLICATE KEY UPDATE c2 = 2;
INSERT INTO t_grammer VALUES(24) ON DUPLICATE KEY UPDATE c2 = length('test') + 100;

-- support without table name
INSERT INTO t_grammer VALUES(31, 1) ON DUPLICATE KEY UPDATE c2 = c1, c4.a = VALUES(c1);
INSERT INTO t_grammer VALUES(32, 2) ON DUPLICATE KEY UPDATE c2 = c1 + 5, c4.a = VALUES(c1);

-- support with table name
INSERT INTO t_grammer VALUES(41, 1) ON DUPLICATE KEY UPDATE c2 = t_grammer.c1, c4.a = VALUES(c1);
INSERT INTO t_grammer VALUES(42, 2) ON DUPLICATE KEY UPDATE c2 = t_grammer.c1 + 5, c4.a = VALUES(c1);

-- support EXCLUDED alone and with expr
INSERT INTO t_grammer VALUES(51, 1) ON DUPLICATE KEY UPDATE c2 = c1 + 5, c4.a = EXCLUDED.c1;
INSERT INTO t_grammer VALUES(52, 2) ON DUPLICATE KEY UPDATE c2 = t_grammer.c1 + 5, c4.a = EXCLUDED.c1 + 5;
INSERT INTO t_grammer VALUES(53, 3) ON DUPLICATE KEY UPDATE c4.a = sqrt(EXCLUDED.c1 - EXCLUDED.c2 - 1) + 1, c2 = t_grammer.c1 + 5;
INSERT INTO t_grammer VALUES(54, 4) ON DUPLICATE KEY UPDATE c4.b = EXCLUDED.c1 + t_grammer.c1;
INSERT INTO t_grammer VALUES(55, 5) ON DUPLICATE KEY UPDATE c4.a = EXCLUDED.c2, c4.b = EXCLUDED.c1 + sqrt(c1 - 6);

-- support ARRAY
INSERT INTO t_grammer VALUES(61, 1) ON DUPLICATE KEY UPDATE c2 = VALUES(c3[1]);
INSERT INTO t_grammer VALUES(62, 2) ON DUPLICATE KEY UPDATE c5 = VALUES(c3[2,3]);
INSERT INTO t_grammer VALUES(63, 3) ON DUPLICATE KEY UPDATE c5 = VALUES(c3[2:3]);
INSERT INTO t_grammer VALUES(64, 4, '{10, 20, 30}') ON DUPLICATE KEY UPDATE c2 = EXCLUDED.c3[1];
INSERT INTO t_grammer VALUES(65, 5, '{10, 20, 30}') ON DUPLICATE KEY UPDATE c5 = EXCLUDED.c3[2,3];
INSERT INTO t_grammer VALUES(66, 6, '{10, 20, 30}') ON DUPLICATE KEY UPDATE c5 = EXCLUDED.c3[1:2];
INSERT INTO t_grammer VALUES(67, 7, '{10, 20, 30}') ON DUPLICATE KEY UPDATE c2 = c3[1];
INSERT INTO t_grammer VALUES(68, 8, '{10, 20, 30}') ON DUPLICATE KEY UPDATE c5 = c3[2,3];
INSERT INTO t_grammer VALUES(69, 9, '{10, 20, 30}') ON DUPLICATE KEY UPDATE c5 = c3[1:2];

-- support user defined type
INSERT INTO t_grammer VALUES(71, 1) ON DUPLICATE KEY UPDATE c4.a = c3[1] + c1;
INSERT INTO t_grammer VALUES(72, 2, '{71, 72, 73}') ON DUPLICATE KEY UPDATE c4.a = c3[1] + c1;
INSERT INTO t_grammer VALUES(73, 3, '{71, 72, 73}') ON DUPLICATE KEY UPDATE c4.a = c3[1] + c1, c4.b = c3[2];
INSERT INTO t_grammer VALUES(74, 4, '{71, 72, 73}', ROW(74, 75)) ON DUPLICATE KEY UPDATE c4 = ROW(740, 750);

-- appoint INSERT target column
INSERT INTO t_grammer (c5, c1, c2) VALUES('{81,82}', 81, DEFAULT) ON DUPLICATE KEY UPDATE c2 = VALUES(c1);
INSERT INTO t_grammer (c3[1], c3[2], c1) VALUES(881, 882, 82) ON DUPLICATE KEY UPDATE c5 = VALUES(c3), c2 = VALUES(c3[1]);
INSERT INTO t_grammer (c1, c3, c4) VALUES(83, '{81, 82, 83}', ROW(810, 820)) ON DUPLICATE KEY UPDATE c4 = EXCLUDED.c4;
INSERT INTO t_grammer (c1, c3, c4.a) VALUES(84, '{81, 82, 83}', 850) ON DUPLICATE KEY UPDATE c4.b = c3[3];

-- support UPDATE NOTHING
INSERT INTO t_grammer VALUES(91, 1, '{91, 92, 93}', ROW(94, 95)) ON DUPLICATE KEY UPDATE NOTHING;
INSERT INTO t_grammer (c5, c1, c2, c4) VALUES('{91,92}', 92, DEFAULT, ROW(910, 920)) ON DUPLICATE KEY UPDATE NOTHING;

-- UPDATE target: unsupport with schema but support with tablename
INSERT INTO t_grammer VALUES(0, 0, '{0,0}', ROW(0, 0), '{107, 108}') ON DUPLICATE KEY UPDATE
	upsert_test.t_grammer.c2 = c2 * 10, upsert_test.t_grammer.c3[1:2] = c5[1:2], upsert_test.t_grammer.c4.a = c1;
INSERT INTO t_grammer VALUES(101, 1, '{102, 103, 104}', ROW(105, 106), '{107, 108}') ON DUPLICATE KEY UPDATE
	t_grammer.c2 = c2 * 10, t_grammer.c3[1:2] = c5[1:2], t_grammer.c4.a = c1;

-- INSERT target: appoint schema
INSERT INTO upsert_test.t_grammer VALUES(102, 2, '{102, 103, 104}', ROW(105, 106), '{107, 108}') ON DUPLICATE KEY UPDATE
	t_grammer.c2 = EXCLUDED.c2 * 10, t_grammer.c3[1:2] = c5[1:2], t_grammer.c4.a = VALUES(c1);
CREATE SCHEMA upsert_test_tmpschema;
SET CURRENT_SCHEMA TO upsert_test_tmpschema;
INSERT INTO upsert_test.t_grammer VALUES(103, 3, '{102, 103, 104}', ROW(105, 106), '{107, 108}') ON DUPLICATE KEY UPDATE
	t_grammer.c2 = EXCLUDED.c2 * 10, t_grammer.c3[1:2] = c5[1:2], t_grammer.c4.a = VALUES(c1);
SET CURRENT_SCHEMA TO upsert_test;
DROP SCHEMA upsert_test_tmpschema;

-- support data type
INSERT INTO t_data VALUES(11, 11, 11, 11, 11, '11', '11', '11', '2020-04-23', '2020-04-23 11:00', '1:00') ON DUPLICATE KEY UPDATE NOTHING;
INSERT INTO t_data VALUES(12, 12, 12, 12, 12, '12', '12', '12', '2020-04-24', '2020-04-24 11:00', '2:00') 
	ON DUPLICATE KEY UPDATE 
	c_tiny = 13, c_smallint = 13, c_bigint = 13, c_numeric = 13,
	c_var = '13', c_text = '13', c_bytea = '13', c_date = '2020-05-24', c_timestamp = '2020-05-24 11:00', c_time = '3:00';
INSERT INTO t_data VALUES(13, 13, 13, 13, 13, '13', '13', '13', '2020-04-25', '2020-04-25 11:00', '4:00') 
	ON DUPLICATE KEY UPDATE 
	c_tiny = EXCLUDED.c_tiny + 1, c_smallint = EXCLUDED.c_smallint + 1, c_bigint = EXCLUDED.c_bigint + 1, c_numeric = EXCLUDED.c_numeric + 1,
	c_var = EXCLUDED.c_var || '3', c_text = EXCLUDED.c_text || '3', c_bytea = EXCLUDED.c_bytea || '3',
	c_date = EXCLUDED.c_date + '1 day'::interval, c_timestamp = EXCLUDED.c_timestamp + '1 day'::interval, c_time = EXCLUDED.c_time + '1 hour'::interval;

-- support UPDATE to default
INSERT INTO t_default DEFAULT VALUES ON DUPLICATE KEY UPDATE c2 = 100, c3 = '2020-05-17';
INSERT INTO t_default VALUES(91, 0.91, '2020-05-17') ON DUPLICATE KEY UPDATE c2 = DEFAULT, c3 = DEFAULT;
INSERT INTO t_default VALUES(92, DEFAULT, '2020-05-17') ON DUPLICATE KEY UPDATE c2 = 10, c3 = DEFAULT;

-- unsupport alias
INSERT INTO t_grammer AS alias VALUES (91) ON DUPLICATE KEY UPDATE c2 = VALUES(c1);

-- unsupport VALUES with expr
INSERT INTO t_grammer VALUES(0, 0) ON DUPLICATE KEY UPDATE c2 = sqrt(VALUES(c2));
INSERT INTO t_grammer VALUES(0, 0) ON DUPLICATE KEY UPDATE c2 = VALUES(c3[1]) + 1;
INSERT INTO t_grammer VALUES(0, 0) ON DUPLICATE KEY UPDATE c2 = VALUES(c4.a) + 1;
INSERT INTO t_grammer VALUES(0, 0) ON DUPLICATE KEY UPDATE c2 = VALUES(t_grammer.c3[1]) + 1;

-- unsupport VALUES with table name
INSERT INTO t_grammer VALUES(0, 0) ON DUPLICATE KEY UPDATE c2 = VALUES(t_grammer.c4.a);
INSERT INTO t_grammer VALUES(0, 0) ON DUPLICATE KEY UPDATE c2 = VALUES(t_grammer.c2);

-- unsupport DEFAULT with expr
INSERT INTO t_grammer VALUES(0, 0) ON DUPLICATE KEY UPDATE c2 = DEFAULT + 1;

-- unsupport user defined typed column's element
INSERT INTO t_grammer VALUES(0, 0) ON DUPLICATE KEY UPDATE c2 = VALUES(c4.a);
INSERT INTO t_grammer VALUES(0, 0) ON DUPLICATE KEY UPDATE c2 = EXCLUDED.c4.a;
INSERT INTO t_grammer VALUES(0, 0) ON DUPLICATE KEY UPDATE c2 = c4.a;

SELECT * FROM t_data ORDER BY 1;
SELECT * FROM t_grammer ORDER BY 1;
SELECT * FROM t_default ORDER BY 1;

-- for table named excluded
INSERT INTO excluded values(1,1),(2,2) ON DUPLICATE KEY UPDATE b = excluded.b + 1;
INSERT INTO "excluded" values(1,1),(2,2) ON DUPLICATE KEY UPDATE b = excluded.b + 1;
INSERT INTO "excluded" values(5,5),(6,6) ON DUPLICATE KEY UPDATE b = 1;
SELECT * FROM excluded;
SELECT * FROM "excluded";
