-- =====================================================================
-- 02  แบบที่ 2: JOIN UUID ที่ปน 4 รูปแบบ ด้วย UNION 3 ก้อน
--
--   - om.order_ref_guid เป็น '{UPPER}' แต่ oi.uuid ปน UPPER / lower / {UPPER} / {lower}
--   - แยกเป็น 3 query ตามรูปแบบ แล้วรวมด้วย UNION (ตัดแถวซ้ำให้)
--   - ข้อเสีย: อ่าน order_inbox 3 รอบ + ต้อง dedupe ผลรวมอีกรอบ
--
-- หมายเหตุ: utf8mb4_general_ci ไม่สนตัวพิมพ์ ก้อนที่ 3 (LOWER) จึงซ้ำกับก้อนที่ 2
--           คงไว้ตามที่ใช้ในคลิป
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
    ON om.order_ref_guid COLLATE utf8mb4_general_ci = oi.uuid COLLATE utf8mb4_general_ci
LEFT JOIN shop_core.zone_master AS zm
    ON zm.zone_code COLLATE utf8mb4_general_ci
     = CONCAT(om.province_code, om.district_code, om.subdistrict_code) COLLATE utf8mb4_general_ci
WHERE oi.order_ts >= UNIX_TIMESTAMP('2026-08-01 00:00:00')
  AND oi.order_ts <= UNIX_TIMESTAMP('2026-08-31 23:59:59')
  AND oi.rec_status COLLATE utf8mb4_general_ci = 'active'
  AND om.sync_date IS NOT NULL
  AND om.cancel_date IS NULL
  AND om.cancel_code IS NULL

UNION

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
    ON om.order_ref_guid COLLATE utf8mb4_general_ci = CONCAT('{', oi.uuid, '}') COLLATE utf8mb4_general_ci
LEFT JOIN shop_core.zone_master AS zm
    ON zm.zone_code COLLATE utf8mb4_general_ci
     = CONCAT(om.province_code, om.district_code, om.subdistrict_code) COLLATE utf8mb4_general_ci
WHERE oi.order_ts >= UNIX_TIMESTAMP('2026-08-01 00:00:00')
  AND oi.order_ts <= UNIX_TIMESTAMP('2026-08-31 23:59:59')
  AND oi.rec_status COLLATE utf8mb4_general_ci = 'active'
  AND om.sync_date IS NOT NULL
  AND om.cancel_date IS NULL
  AND om.cancel_code IS NULL

UNION

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
    ON om.order_ref_guid COLLATE utf8mb4_general_ci = CONCAT('{', LOWER(oi.uuid), '}') COLLATE utf8mb4_general_ci
LEFT JOIN shop_core.zone_master AS zm
    ON zm.zone_code COLLATE utf8mb4_general_ci
     = CONCAT(om.province_code, om.district_code, om.subdistrict_code) COLLATE utf8mb4_general_ci
WHERE oi.order_ts >= UNIX_TIMESTAMP('2026-08-01 00:00:00')
  AND oi.order_ts <= UNIX_TIMESTAMP('2026-08-31 23:59:59')
  AND oi.rec_status COLLATE utf8mb4_general_ci = 'active'
  AND om.sync_date IS NOT NULL
  AND om.cancel_date IS NULL
  AND om.cancel_code IS NULL;
