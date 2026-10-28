-- =====================================================================
-- CASE STUDY: ทำไม JOIN ช้า? (MySQL 8.0+)
-- ธีมร้านค้าออนไลน์ — ใช้สอน/ทำคลิปได้ ไม่มีข้อมูลงานจริง
--
--   shop_core.order_master  = ตารางหลัก   PK  order_ref_guid  -> '{UUID ตัวใหญ่}'
--   shop_web.order_inbox    = ตารางฝั่งเว็บ PK  id  + คอลัมน์ uuid  -> ปน 4 รูปแบบ
--
-- 2 คอลัมน์คีย์ที่ใช้ join: id, uuid (ฝั่งเว็บ) กับ order_ref_guid (ฝั่งหลัก)
--
-- วิธีใช้
--   1) รันทั้งไฟล์ 1 ครั้ง  (สร้างตาราง + procedure + ข้อมูลชุดแรก 1,000,000)
--   2) เพิ่มข้อมูลอีกเมื่อไรก็ได้:  CALL sp_mock_shop_data(100000, 90, 10);
-- =====================================================================

CREATE DATABASE IF NOT EXISTS shop_core CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS shop_web  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE shop_web;

-- ---------------------------------------------------------------------
-- 1. SCHEMA
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS shop_core.order_master;
CREATE TABLE shop_core.order_master (
  order_ref_guid VARCHAR(38) NOT NULL COMMENT 'คีย์อ้างอิงจากระบบต้นทาง รูปแบบ {UUID ตัวใหญ่}',
  shop_code        VARCHAR(9)   DEFAULT NULL,
  customer_code    VARCHAR(15)  DEFAULT NULL,
  order_date       DATE         DEFAULT NULL,
  channel_code     VARCHAR(3)   DEFAULT NULL COMMENT 'ช่องทางขาย',
  customer_name    VARCHAR(150) DEFAULT NULL,
  customer_phone   VARCHAR(60)  DEFAULT NULL,
  ship_address     VARCHAR(150) DEFAULT NULL,
  ship_building    VARCHAR(40)  DEFAULT NULL,
  ship_road        VARCHAR(150) DEFAULT NULL,
  province_code    VARCHAR(2)   DEFAULT NULL,
  district_code    VARCHAR(2)   DEFAULT NULL,
  subdistrict_code VARCHAR(2)   DEFAULT NULL,
  bill_province    VARCHAR(2)   DEFAULT NULL,
  bill_district    VARCHAR(2)   DEFAULT NULL,
  bill_subdistrict VARCHAR(2)   DEFAULT NULL,
  item_qty         SMALLINT     DEFAULT NULL,
  total_amount     DECIMAL(12,2) DEFAULT NULL,
  discount_amount  DECIMAL(12,2) DEFAULT NULL,
  payment_method   VARCHAR(10)  DEFAULT NULL,
  order_status     SMALLINT     DEFAULT NULL,
  courier_code     VARCHAR(10)  DEFAULT NULL,
  tracking_no      VARCHAR(30)  DEFAULT NULL,
  note             VARCHAR(255) DEFAULT NULL,
  sync_date        DATETIME     DEFAULT NULL COMMENT 'วันที่ sync สำเร็จ (NULL = ยังไม่ sync)',
  cancel_date      DATETIME     DEFAULT NULL COMMENT 'วันที่ยกเลิก (NULL = ยังไม่ยกเลิก)',
  cancel_code      VARCHAR(50)  DEFAULT NULL,
  update_datetime  DATETIME     NOT NULL,
  rec_status       VARCHAR(20)  DEFAULT NULL,
  PRIMARY KEY (order_ref_guid),
  UNIQUE KEY uk_order_shop (shop_code, customer_code, channel_code, order_date) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS order_inbox;
CREATE TABLE order_inbox (
  id            INT         NOT NULL AUTO_INCREMENT,
  uuid          VARCHAR(40) NOT NULL COMMENT 'คีย์อ้างอิง — ปน 4 รูปแบบ: UPPER / lower / {UPPER} / {lower}',
  product_name  VARCHAR(250) DEFAULT NULL,
  sku           VARCHAR(20)  DEFAULT NULL,
  category      VARCHAR(120) DEFAULT NULL,
  brand         VARCHAR(120) DEFAULT NULL,
  qty           INT          DEFAULT NULL,
  unit_price    DECIMAL(12,2) DEFAULT NULL,
  line_total    DECIMAL(12,2) DEFAULT NULL,
  coupon_code   VARCHAR(20)  DEFAULT NULL,
  buyer_name    VARCHAR(160) DEFAULT NULL,
  buyer_phone   VARCHAR(80)  DEFAULT NULL,
  buyer_email   VARCHAR(120) DEFAULT NULL,
  address_no    VARCHAR(80)  DEFAULT NULL,
  address_soi   VARCHAR(250) DEFAULT NULL,
  address_road  VARCHAR(120) DEFAULT NULL,
  subdistrict   VARCHAR(120) DEFAULT NULL,
  district      VARCHAR(120) DEFAULT NULL,
  province      VARCHAR(120) DEFAULT NULL,
  postcode      VARCHAR(8)   DEFAULT NULL,
  channel       VARCHAR(20)  DEFAULT NULL,
  order_ts      BIGINT       DEFAULT NULL COMMENT 'เวลาที่สั่ง (Unix Timestamp)',
  paid_ts       BIGINT       DEFAULT NULL,
  ship_date     DATE         DEFAULT NULL,
  state         VARCHAR(4)   NOT NULL DEFAULT '0',
  batch_name    VARCHAR(240) DEFAULT NULL,
  remark        VARCHAR(255) DEFAULT NULL,
  rec_status    VARCHAR(20)  NOT NULL DEFAULT 'active',
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 2. PROCEDURE สร้าง mock data (เรียกซ้ำได้ ไม่ชน unique key เดิม)
--    p_rows       จำนวนแถวที่จะเพิ่มใน order_master
--    p_match_pct  % ที่จะมีคู่ใน order_inbox      (default 90)
--    p_noise_pct  % ของ noise ที่ uuid ไม่มีคู่   (default 10)
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_mock_shop_data;

DELIMITER $$
CREATE PROCEDURE sp_mock_shop_data(
    IN p_rows      INT,
    IN p_match_pct INT,
    IN p_noise_pct INT
)
BEGIN
    DECLARE v_offset BIGINT;
    DECLARE v_batch  VARCHAR(20);

    SET p_match_pct = IFNULL(p_match_pct, 90);
    SET p_noise_pct = IFNULL(p_noise_pct, 10);
    SET SESSION cte_max_recursion_depth = 5000000;

    SELECT COUNT(*) INTO v_offset FROM shop_core.order_master;
    SET v_batch = CONCAT('B', DATE_FORMAT(NOW(), '%y%m%d%H%i%s'));

    -- 2.1 ชุด guid ของรอบนี้
    DROP TEMPORARY TABLE IF EXISTS tmp_gen;
    CREATE TEMPORARY TABLE tmp_gen (
        n    INT PRIMARY KEY,
        guid CHAR(36) NOT NULL,
        prov VARCHAR(2), dist VARCHAR(2), subd VARCHAR(2),
        shop VARCHAR(9), cust VARCHAR(13), chan VARCHAR(3),
        odate DATE, cname VARCHAR(60), phone VARCHAR(20),
        qty INT, price DECIMAL(12,2)
    ) ENGINE=InnoDB;

    INSERT INTO tmp_gen
    WITH RECURSIVE seq AS (
        SELECT 1 AS n UNION ALL SELECT n + 1 FROM seq WHERE n < p_rows
    )
    SELECT
        n,
        UPPER(UUID()),
        IF(RAND() < 0.7, '10', LPAD(11 + FLOOR(RAND()*66), 2, '0')),
        LPAD(1 + FLOOR(RAND()*50), 2, '0'),
        LPAD(1 + FLOOR(RAND()*10), 2, '0'),
        ELT(1 + FLOOR(RAND()*6), 'SHOP0001','SHOP0002','SHOP0003','SHOP0004','SHOP0005','SHOP0006'),
        LPAD(v_offset + n, 13, '0'),
        ELT(1 + FLOOR(RAND()*5), 'WEB','APP','LIN','SHP','LZD'),
        DATE('2026-01-01') + INTERVAL FLOOR(RAND()*250) DAY,
        CONCAT(ELT(1 + FLOOR(RAND()*8), 'สมชาย','สมหญิง','วิชัย','อรุณ','กมล','ปิยะ','ธนา','นภา'),
               ' ',
               ELT(1 + FLOOR(RAND()*8), 'ใจดี','รักไทย','ศรีสุข','ทองดี','มั่นคง','สุขสันต์','แซ่ลิ้ม','วงศ์ใหญ่')),
        CONCAT('08', LPAD(FLOOR(RAND()*99999999), 8, '0')),
        1 + FLOOR(RAND()*5),
        ROUND(50 + RAND()*4950, 2)
    FROM seq;

    -- 2.2 ตารางหลัก: guid เป็น {UPPER} เสมอ
    INSERT INTO shop_core.order_master (
        order_ref_guid, shop_code, customer_code, order_date, channel_code,
        customer_name, customer_phone, ship_address, ship_building, ship_road,
        province_code, district_code, subdistrict_code,
        bill_province, bill_district, bill_subdistrict,
        item_qty, total_amount, discount_amount, payment_method, order_status,
        courier_code, tracking_no, note, sync_date, cancel_date, cancel_code,
        update_datetime, rec_status
    )
    SELECT
        CONCAT('{', g.guid, '}'),
        g.shop, g.cust, g.odate, g.chan,
        g.cname, g.phone,
        CONCAT(1 + FLOOR(RAND()*999), '/', 1 + FLOOR(RAND()*50)),
        CONCAT('อาคาร ', CHAR(65 + FLOOR(RAND()*26))),
        CONCAT('ถนน', ELT(1 + FLOOR(RAND()*5), 'สุขุมวิท','ลาดพร้าว','พหลโยธิน','รามคำแหง','เพชรบุรี')),
        g.prov, g.dist, g.subd,
        -- ที่อยู่ใบกำกับ: 60% เว้นว่าง/NULL  (ไว้ทำเคส IS NULL / = '')
        g.prov,
        IF(RAND() < 0.6, IF(RAND() < 0.5, '', NULL), g.dist),
        IF(RAND() < 0.6, IF(RAND() < 0.5, '', NULL), g.subd),
        g.qty, ROUND(g.qty * g.price, 2), ROUND(g.price * 0.1, 2),
        ELT(1 + FLOOR(RAND()*4), 'COD','CARD','QR','BANK'),
        1 + FLOOR(RAND()*4),
        ELT(1 + FLOOR(RAND()*4), 'KERRY','FLASH','JT','THPOST'),
        CONCAT('TH', LPAD(v_offset + g.n, 11, '0')),
        v_batch,
        -- 70% sync แล้ว / 10% ยกเลิก  (ไว้ทำเคส IS NOT NULL + IS NULL)
        IF(RAND() < 0.7, g.odate + INTERVAL FLOOR(RAND()*3) DAY, NULL),
        IF(RAND() < 0.1, g.odate + INTERVAL FLOOR(RAND()*30) DAY, NULL),
        IF(RAND() < 0.1, CONCAT('CXL', LPAD(FLOOR(RAND()*9999), 4, '0')), NULL),
        g.odate + INTERVAL FLOOR(RAND()*172800) SECOND,
        'active'
    FROM tmp_gen g;

    -- 2.3 ฝั่งเว็บ (ที่ match): uuid สุ่ม 4 รูปแบบ  <<< หัวใจของเคสนี้
    INSERT INTO order_inbox (
        uuid, product_name, sku, category, brand, qty, unit_price, line_total, coupon_code,
        buyer_name, buyer_phone, buyer_email, address_no, address_soi, address_road,
        subdistrict, district, province, postcode, channel,
        order_ts, paid_ts, ship_date, state, batch_name, rec_status
    )
    SELECT
        CASE FLOOR(RAND()*4)
            WHEN 0 THEN g.guid                            -- UPPER
            WHEN 1 THEN LOWER(g.guid)                     -- lower
            WHEN 2 THEN CONCAT('{', g.guid, '}')          -- {UPPER}
            ELSE        CONCAT('{', LOWER(g.guid), '}')   -- {lower}
        END,
        ELT(1 + FLOOR(RAND()*6), 'หูฟังไร้สาย','เคสมือถือ','สายชาร์จ','พาวเวอร์แบงค์','ลำโพงบลูทูธ','ขาตั้งมือถือ'),
        CONCAT('SKU', LPAD(FLOOR(RAND()*99999), 5, '0')),
        ELT(1 + FLOOR(RAND()*4), 'Electronics','Accessories','Gadget','Home'),
        ELT(1 + FLOOR(RAND()*5), 'BrandA','BrandB','BrandC','BrandD','BrandE'),
        g.qty, g.price, ROUND(g.qty * g.price, 2),
        IF(RAND() < 0.3, CONCAT('CP', LPAD(FLOOR(RAND()*999), 3, '0')), NULL),
        g.cname, g.phone,
        CONCAT('user', v_offset + g.n, '@example.com'),
        CONCAT(1 + FLOOR(RAND()*999)),
        CONCAT('ซอย ', 1 + FLOOR(RAND()*60)),
        CONCAT('ถนน', ELT(1 + FLOOR(RAND()*5), 'สุขุมวิท','ลาดพร้าว','พหลโยธิน','รามคำแหง','เพชรบุรี')),
        CONCAT(g.prov, g.dist, g.subd), CONCAT(g.prov, g.dist), g.prov,
        CONCAT('10', LPAD(FLOOR(RAND()*999), 3, '0')),
        g.chan,
        UNIX_TIMESTAMP(g.odate) + FLOOR(RAND()*86400),
        UNIX_TIMESTAMP(g.odate) + FLOOR(RAND()*172800),
        g.odate + INTERVAL 1 DAY,
        '0', v_batch, 'active'
    FROM tmp_gen g
    WHERE RAND() * 100 < p_match_pct;

    -- 2.4 noise: uuid ที่ไม่มีคู่ในตารางหลัก
    INSERT INTO order_inbox (uuid, product_name, qty, unit_price, buyer_name,
                             order_ts, state, batch_name, rec_status)
    WITH RECURSIVE seq AS (
        SELECT 1 AS n UNION ALL SELECT n + 1 FROM seq WHERE n < GREATEST(1, FLOOR(p_rows * p_noise_pct / 100))
    )
    SELECT
        CASE FLOOR(RAND()*4)
            WHEN 0 THEN UPPER(UUID()) WHEN 1 THEN UUID()
            WHEN 2 THEN CONCAT('{', UPPER(UUID()), '}') ELSE CONCAT('{', UUID(), '}')
        END,
        'สินค้าทดสอบ (ไม่มีคู่)', 1, 0.00, 'ทดสอบ ระบบ',
        UNIX_TIMESTAMP('2026-01-01') + FLOOR(RAND()*250*86400),
        '0', v_batch, 'active'
    FROM seq;

    DROP TEMPORARY TABLE IF EXISTS tmp_gen;

    SELECT v_batch AS batch,
           (SELECT COUNT(*) FROM shop_core.order_master) AS total_order_master,
           (SELECT COUNT(*) FROM order_inbox)            AS total_order_inbox;
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- 3. สร้างข้อมูลชุดแรก
-- ---------------------------------------------------------------------
CALL sp_mock_shop_data(1000000, 90, 10);
-- เพิ่มอีกเมื่อไรก็ได้:  CALL sp_mock_shop_data(100000, 90, 10);

-- กระจาย order_ts ให้ปี 2026 เหลือ 30% (ที่เหลือไปปี 2024/2025/2027)
SET SQL_SAFE_UPDATES = 0;
UPDATE order_inbox oi
JOIN (SELECT id, RAND() AS r FROM order_inbox) x ON x.id = oi.id
SET oi.order_ts = CASE
      WHEN x.r < 0.30 THEN UNIX_TIMESTAMP('2026-01-01') + FLOOR(RAND()*365*86400)
      WHEN x.r < 0.55 THEN UNIX_TIMESTAMP('2024-01-01') + FLOOR(RAND()*365*86400)
      WHEN x.r < 0.80 THEN UNIX_TIMESTAMP('2025-01-01') + FLOOR(RAND()*365*86400)
      ELSE                 UNIX_TIMESTAMP('2027-01-01') + FLOOR(RAND()*365*86400)
    END;

ANALYZE TABLE order_inbox;
ANALYZE TABLE shop_core.order_master;