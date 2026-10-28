-- =====================================================================
-- 03  แบบที่ 2: รวม 3 ก้อนของ UNION เป็น JOIN ... ON ... IN (...)
--
--   - อ่าน order_inbox รอบเดียว ไม่ต้อง dedupe
--   - ผลลัพธ์ต้องได้แถวเท่ากับ 02_join_union.sql (เช็กด้วย 04_compare.sql)
--   - ทั้งสองแบบยังครอบ column ด้วย COLLATE / CONCAT / LOWER
--     จึงใช้ PRIMARY KEY ของ order_master หาแบบตรง ๆ ไม่ได้
-- =====================================================================

-- EXPLAIN ANALYZE
SELECT
    oi.id,
    oi.uuid,
    om.order_ref_guid,
    oi.sku,
    om.shop_code,
    om.total_amount,
    CONCAT(om.province_code, om.district_code, om.subdistrict_code) AS zone_code_full,
    zm.zone_name,
    zm.area_name,
    zm.region_name,
    zm.delivery_fee
FROM shop_web.order_inbox AS oi
JOIN shop_core.order_master AS om
    ON om.order_ref_guid COLLATE utf8mb4_general_ci IN (
           oi.uuid                                COLLATE utf8mb4_general_ci,   -- {UPPER} / {lower}
           CONCAT('{', oi.uuid, '}')              COLLATE utf8mb4_general_ci,   -- UPPER / lower
           CONCAT('{', LOWER(oi.uuid), '}')       COLLATE utf8mb4_general_ci    -- (ซ้ำเมื่อเป็น _ci)
       )
LEFT JOIN shop_core.zone_master AS zm
    ON zm.zone_code COLLATE utf8mb4_general_ci
     = CONCAT(om.province_code, om.district_code, om.subdistrict_code) COLLATE utf8mb4_general_ci
WHERE oi.order_ts >= UNIX_TIMESTAMP('2026-08-01 00:00:00')
  AND oi.order_ts <= UNIX_TIMESTAMP('2026-08-31 23:59:59')
  AND oi.rec_status COLLATE utf8mb4_general_ci = 'active'
  AND om.sync_date IS NOT NULL
  AND om.cancel_date IS NULL
  AND om.cancel_code IS NULL;
