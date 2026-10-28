-- =====================================================================
-- 04  เทียบ UNION vs IN
--
--   ขั้นที่ 1  ผลลัพธ์ต้องเท่ากัน (จำนวนแถว และแถวที่ต่างกันต้องเป็น 0)
--   ขั้นที่ 2  วัดเวลา: เปิด EXPLAIN ANALYZE ในไฟล์ 02 และ 03 แล้วรันทีละไฟล์
--              รันแต่ละไฟล์ 2 รอบ ใช้ผลรอบที่ 2 (ตัดผลของ cache เย็น)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) จำนวนแถว (oi.id ไม่ซ้ำต่อแถว ใช้นับได้)
-- ---------------------------------------------------------------------
WITH
f AS (
    SELECT oi.id, oi.uuid, om.order_ref_guid,
           CONCAT(om.province_code, om.district_code, om.subdistrict_code) AS zone_code_full
    FROM shop_web.order_inbox AS oi
    JOIN shop_core.order_master AS om
      ON om.order_ref_guid COLLATE utf8mb4_general_ci IN (
             oi.uuid                          COLLATE utf8mb4_general_ci,
             CONCAT('{', oi.uuid, '}')        COLLATE utf8mb4_general_ci,
             CONCAT('{', LOWER(oi.uuid), '}') COLLATE utf8mb4_general_ci)
    WHERE oi.order_ts >= UNIX_TIMESTAMP('2026-08-01 00:00:00')
      AND oi.order_ts <= UNIX_TIMESTAMP('2026-08-31 23:59:59')
      AND oi.rec_status COLLATE utf8mb4_general_ci = 'active'
      AND om.sync_date IS NOT NULL AND om.cancel_date IS NULL AND om.cancel_code IS NULL
),
u AS (
    SELECT oi.id
    FROM shop_web.order_inbox AS oi
    JOIN shop_core.order_master AS om
      ON om.order_ref_guid COLLATE utf8mb4_general_ci = oi.uuid COLLATE utf8mb4_general_ci
    WHERE oi.order_ts >= UNIX_TIMESTAMP('2026-08-01 00:00:00')
      AND oi.order_ts <= UNIX_TIMESTAMP('2026-08-31 23:59:59')
      AND oi.rec_status COLLATE utf8mb4_general_ci = 'active'
      AND om.sync_date IS NOT NULL AND om.cancel_date IS NULL AND om.cancel_code IS NULL
    UNION
    SELECT oi.id
    FROM shop_web.order_inbox AS oi
    JOIN shop_core.order_master AS om
      ON om.order_ref_guid COLLATE utf8mb4_general_ci = CONCAT('{', oi.uuid, '}') COLLATE utf8mb4_general_ci
    WHERE oi.order_ts >= UNIX_TIMESTAMP('2026-08-01 00:00:00')
      AND oi.order_ts <= UNIX_TIMESTAMP('2026-08-31 23:59:59')
      AND oi.rec_status COLLATE utf8mb4_general_ci = 'active'
      AND om.sync_date IS NOT NULL AND om.cancel_date IS NULL AND om.cancel_code IS NULL
    UNION
    SELECT oi.id
    FROM shop_web.order_inbox AS oi
    JOIN shop_core.order_master AS om
      ON om.order_ref_guid COLLATE utf8mb4_general_ci = CONCAT('{', LOWER(oi.uuid), '}') COLLATE utf8mb4_general_ci
    WHERE oi.order_ts >= UNIX_TIMESTAMP('2026-08-01 00:00:00')
      AND oi.order_ts <= UNIX_TIMESTAMP('2026-08-31 23:59:59')
      AND oi.rec_status COLLATE utf8mb4_general_ci = 'active'
      AND om.sync_date IS NOT NULL AND om.cancel_date IS NULL AND om.cancel_code IS NULL
)
SELECT
    (SELECT COUNT(*) FROM f)                                       AS rows_in,
    (SELECT COUNT(*) FROM u)                                       AS rows_union,
    (SELECT COUNT(*) FROM f WHERE id NOT IN (SELECT id FROM u))    AS only_in,
    (SELECT COUNT(*) FROM u WHERE id NOT IN (SELECT id FROM f))    AS only_union;
-- ต้องได้ rows_in = rows_union และ only_in = only_union = 0

-- ---------------------------------------------------------------------
-- 2) แต่ละรูปแบบของ uuid match ได้กี่แถว (ไว้อธิบายในคลิป)
-- ---------------------------------------------------------------------
SELECT
    CASE
        WHEN uuid LIKE '{%' AND BINARY uuid = BINARY UPPER(uuid) THEN '{UPPER}'
        WHEN uuid LIKE '{%'                                       THEN '{lower}'
        WHEN BINARY uuid = BINARY UPPER(uuid)                    THEN 'UPPER'
        ELSE                                                           'lower'
    END      AS uuid_format,
    COUNT(*) AS rows_cnt
FROM shop_web.order_inbox
WHERE order_ts >= UNIX_TIMESTAMP('2026-08-01 00:00:00')
  AND order_ts <= UNIX_TIMESTAMP('2026-08-31 23:59:59')
GROUP BY uuid_format
ORDER BY uuid_format;

-- ---------------------------------------------------------------------
-- 3) ดูเวลาของ 2 query ล่าสุดใน session นี้ (MySQL 8.0.28+)
--    รัน 02 และ 03 ใน tab เดียวกันก่อน แล้วค่อยรันส่วนนี้
-- ---------------------------------------------------------------------
SELECT EVENT_ID,
       LEFT(SQL_TEXT, 80)           AS sql_text,
       ROUND(TIMER_WAIT / 1e12, 3) AS total_s,
       ROUND(CPU_TIME   / 1e12, 3) AS cpu_s,
       ROWS_EXAMINED
FROM performance_schema.events_statements_history
WHERE THREAD_ID = PS_CURRENT_THREAD_ID()
ORDER BY EVENT_ID DESC
LIMIT 5;
