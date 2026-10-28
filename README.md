# ทำไม JOIN ช้า? — UUID ปน 4 รูปแบบ: UNION vs IN (MySQL)

โค้ดประกอบคลิปของ **DevHops** [Facebook](https://www.facebook.com/share/19ruKTdPCk/)) · [Tiktok](https://www.tiktok.com/@devhopsss)) ·([Youtube](https://www.youtube.com/@devhops) · [godevhops.com](https://godevhops.com))  

เคสจำลองร้านค้าออนไลน์ ข้อมูลทั้งหมดเป็น mock data ไม่มีข้อมูลงานจริง
สองตาราง join กันด้วย UUID แต่ฝั่งหลักเก็บเป็น `{UPPER}` ส่วนฝั่งเว็บปนมา 4 รูปแบบ
(`UPPER` / `lower` / `{UPPER}` / `{lower}`) คลิปนี้เทียบสองวิธี join ที่พบบ่อย

1. **IN** — ใส่ทุกรูปแบบไว้ใน `JOIN ... ON ... IN (...)` ตัวเดียว
2. **UNION** — แยก query ตามรูปแบบ แล้วรวมผล

## ตาราง

| ตาราง | PK | คีย์ที่ใช้ join |
|---|---|---|
| `shop_core.order_master` | `order_ref_guid` | `{UUID ตัวใหญ่}` |
| `shop_web.order_inbox` | `id` (AUTO_INCREMENT) | `uuid` ปน 4 รูปแบบ |
| `shop_core.zone_master` | `id` | `zone_code` (จังหวัด+อำเภอ+ตำบล) |

## ลำดับการรัน

| ไฟล์ | ทำอะไร |
|---|---|
| `sql/00_setup_mock_data.sql` | สร้าง database, ตาราง, procedure และข้อมูล 1,000,000 แถว |
| `sql/01_join_in.sql` | แบบที่ 2 — `JOIN ... IN (...)` |
| `sql/02_join_union.sql` | แบบที่ 1 — `UNION` 3 ก้อน |

วัดเวลาด้วยการเปิด `EXPLAIN ANALYZE` ที่หัว query ในไฟล์ 01 และ 02 รันแต่ละไฟล์ 2 รอบ แล้วใช้รอบที่ 2

เพิ่มข้อมูลได้ตลอดด้วย

```sql
CALL shop_web.sp_mock_shop_data(100000, 90, 10);  -- แถว, % ที่มีคู่, % noise
```

## ข้อสังเกต

- `utf8mb4_general_ci` ไม่สนตัวพิมพ์ เงื่อนไขที่ใช้ `LOWER()` จึงซ้ำกับเงื่อนไข `CONCAT('{', uuid, '}')` คงไว้ตามที่ใช้ในคลิป
- ทั้งสองแบบยังครอบ column ด้วย `COLLATE` / `CONCAT` ใน `ON` และ `WHERE` ทำให้ใช้ index ได้ไม่เต็มที่ ทางแก้จริงอยู่ในตอนถัดไปของซีรีส์
- ตัวเลขเวลาขึ้นกับเครื่องและ `innodb_buffer_pool_size` ลองรันบนเครื่องตัวเองเทียบดู

## License

MIT — เอาไปใช้สอน ทดลอง หรือดัดแปลงได้ตามสบาย
