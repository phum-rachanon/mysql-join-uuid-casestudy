-- =====================================================================
-- 01  สร้าง shop_core.zone_master จากรหัสพื้นที่ที่มีใน order_master
--     รันหลัง 00_setup_mock_data.sql (รันซ้ำได้ เพิ่มเฉพาะ zone ใหม่)
--
--     ตั้งใจให้ PK เป็น id และ zone_code เป็น secondary index
--     เพื่อให้เห็นผลของ covering index ใน 05_indexes.sql
-- =====================================================================

CREATE TABLE IF NOT EXISTS shop_core.zone_master (
  id           INT          NOT NULL AUTO_INCREMENT,
  zone_code    VARCHAR(6)   NOT NULL COMMENT 'province + district + subdistrict (2+2+2)',
  zone_name    VARCHAR(120) DEFAULT NULL,
  area_name    VARCHAR(120) DEFAULT NULL,
  region_name  VARCHAR(60)  DEFAULT NULL,
  delivery_fee DECIMAL(8,2) DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_zone_code (zone_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO shop_core.zone_master (zone_code, zone_name, area_name, region_name, delivery_fee)
SELECT
    z.zone_code,
    CONCAT('ตำบล ', z.subd, ' / อำเภอ ', z.dist),
    CONCAT('จังหวัด ', z.prov),
    CASE
        WHEN z.prov = '10'               THEN 'กรุงเทพฯ และปริมณฑล'
        WHEN z.prov BETWEEN '11' AND '29' THEN 'ภาคกลาง'
        WHEN z.prov BETWEEN '30' AND '49' THEN 'ภาคตะวันออกเฉียงเหนือ'
        WHEN z.prov BETWEEN '50' AND '66' THEN 'ภาคเหนือ'
        ELSE                                   'ภาคใต้'
    END,
    IF(z.prov = '10', 40.00, 60.00 + FLOOR(RAND() * 5) * 10)
FROM (
    SELECT DISTINCT
           CONCAT(province_code, district_code, subdistrict_code) AS zone_code,
           province_code AS prov, district_code AS dist, subdistrict_code AS subd
    FROM shop_core.order_master
) z
WHERE NOT EXISTS (
    SELECT 1 FROM shop_core.zone_master zm WHERE zm.zone_code = z.zone_code
);

ANALYZE TABLE shop_core.zone_master;

-- index ตั้งต้นของ order_inbox (แบบที่ระบบส่วนใหญ่มีอยู่: ขึ้นต้นด้วยเวลา)
-- ไม่มี IF NOT EXISTS ใน MySQL ถ้ารันซ้ำจะเจอ Error 1061 ข้ามได้
ALTER TABLE shop_web.order_inbox
  ADD INDEX idx_ts_status (order_ts, rec_status);

SELECT COUNT(*) AS total_zones FROM shop_core.zone_master;
