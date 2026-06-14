# คู่มือทดสอบ Lab 6 — Nanos × Firecracker (สำหรับผู้ทดสอบ)

ทำตามทีละขั้น ไม่ต้องมีความรู้ Nanos/Firecracker มาก่อน
เป้าหมาย: พิสูจน์ว่า lab **ติดตั้งเอง บูตจริง และวัดเวลาได้จริง** บนเครื่อง Linux ของคุณ

> ⏱ ใช้เวลา ~5–10 นาที (ครั้งแรกนานหน่อยถ้าต้องดาวน์โหลด ops/firecracker)

---

## ✅ ขั้นที่ 0 — เช็กก่อนว่าเครื่องพร้อม

ต้องเป็น **Linux ที่มี KVM** (Mac/Windows รันไม่ได้ — Firecracker ต้องการ `/dev/kvm`)

รันเช็ก 3 บรรทัดนี้บนเครื่องที่จะทดสอบ:

```bash
uname -s            # ต้องได้ "Linux"
ls -l /dev/kvm      # ต้องมีไฟล์นี้ (ถ้าไม่มี = เครื่องไม่เปิด virtualization)
sudo -v             # ต้องใช้ sudo ได้
```

ผ่านทั้ง 3 → ไปต่อ. ไม่ผ่าน → ใช้ VPS/cloud ที่เปิด **nested virtualization** หรือ bare-metal Linux

---

## ✅ ขั้นที่ 1 — เอาไฟล์ lab ขึ้นเครื่องทดสอบ

ถ้าทดสอบบนเครื่องเดียวกับที่มีไฟล์อยู่แล้ว ข้ามขั้นนี้ได้

```bash
# จากเครื่องที่มีโฟลเดอร์ lab → คัดทั้งโฟลเดอร์ขึ้นเครื่องทดสอบ
scp -r nanos-microvm-lab  user@<เครื่องทดสอบ>:~/
```

> สำคัญ: ต้องเอา **ทั้งโฟลเดอร์** ไป (ในนั้นมี `lab6_files/` ที่จำเป็น) ไม่ใช่แค่ไฟล์ `.sh` ไฟล์เดียว

---

## ✅ ขั้นที่ 2 — รัน lab

```bash
cd ~/nanos-microvm-lab
./lab6_nanos_microvm.sh
```

ตอนรัน สคริปต์จะทำให้เองทั้งหมด (ไม่ต้องเตรียมอะไรล่วงหน้า):

| ขั้น | สิ่งที่เกิด |
|------|-----------|
| 0 | ตรวจ Linux/KVM/sudo · **ติดตั้งของที่ขาดให้เอง** (gcc, firecracker, ops, kernel) |
| 1 | build HTTP server เล็ก ๆ → สร้างเป็น Nanos unikernel image |
| 2 | บูตบน Firecracker → จับเวลา **cold boot** จนเสิร์ฟได้ |
| 3 | ทำ **snapshot** → วัดเวลา + ขนาด |
| 4 | **restore** กลับ 5 รอบ → จับเวลา "ปลุกจาก snapshot" |
| 5 | ดึงหน้าเว็บจริงมายืนยัน + เซฟผล |

---

## ✅ ขั้นที่ 3 — ดูว่า"ผ่าน" หน้าตาเป็นยังไง

ระหว่างรัน ควรเห็นบรรทัดทำนองนี้ (ตัวเลขจะต่างกันไปตามเครื่อง):

```
[driver] COLD boot → service-ready 380.0 ms          ← บูตสด แล้วเสิร์ฟได้
[driver] GET / → HTTP/1.1 200 OK · 412 bytes         ← เสิร์ฟหน้าเว็บจริง
[driver] SNAPSHOT created 95.0 ms · mem-file 64.0 MB  ← snapshot สำเร็จ
[driver] RESTORE 1/5 → service-ready 16.0 ms          ← ปลุกเร็วกว่า cold มาก
...
✅ สำเร็จ — ผลวัดสดอยู่ใน ~/nanos-microvm-lab/results.json
```

**เกณฑ์ผ่าน** (ดู 3 อย่าง):
1. มีบรรทัด `COLD boot → service-ready <ms>` (ไม่ใช่ error)
2. `GET / → HTTP/1.1 200 OK` + bytes > 0
3. มี `RESTORE x/5 → service-ready <ms>` และ **restore < cold boot ชัดเจน**

> 💡 ตัวเลขด้านบนเป็นแค่ "หน้าตาตัวอย่าง" — ของจริงขึ้นกับเครื่องคุณ ทุกค่าวัดสด ไม่มี hardcoded

---

## ✅ ขั้นที่ 4 — ตรวจผลลัพธ์ที่เซฟไว้

```bash
cat ~/nanos-microvm-lab/results.json          # ตัวเลขทั้งหมด (cold/snapshot/restore)
cat ~/nanos-microvm-lab/served_page.html      # หน้าเว็บจริงที่ unikernel เสิร์ฟกลับมา
```

`results.json` จะมีโครงประมาณนี้ (ค่าเป็นของเครื่องคุณ):

```json
{
  "mem_mib": 128,
  "cold_boot_ms": 380.0,
  "served_status": "HTTP/1.1 200 OK",
  "served_bytes": 412,
  "snap_create_ms": 95.0,
  "snap_mem_mb": 64.0,
  "restore_wake": { "n": 5, "median": 16.0, "min": 14.2, "max": 18.9, "sd": 1.7 }
}
```

---

## ✅ ขั้นที่ 5 — ลองปรับ (ถ้าอยากดูเพิ่ม)

```bash
./lab6_nanos_microvm.sh --restores 20   # restore 20 รอบ → median เสถียรขึ้น
./lab6_nanos_microvm.sh --mem 256       # จอง RAM 256 MiB (ดูผลต่อ snapshot size/boot)
```

---

## ✅ ขั้นที่ 6 — ล้างให้สะอาด (หลังทดสอบเสร็จ)

```bash
./lab6_nanos_microvm.sh --clean         # ลบ workdir + ลบ tap network ทิ้ง
```

---

## 🔧 ถ้าไม่ผ่าน — เช็กตามนี้

| อาการบนจอ | แปลว่า / แก้ยังไง |
|-----------|------------------|
| `ต้องเป็น Linux` / `ไม่มี /dev/kvm` | เครื่องไม่รองรับ KVM → เปลี่ยนเครื่อง (ขั้น 0) |
| ค้างที่ `ติดตั้ง ops/firecracker` | เน็ตมีปัญหา → ตรวจ internet แล้วรันใหม่ |
| `guest ไม่ตอบ 200 ... ดู cold.log` | guest บูตไม่ขึ้น → เปิด `~/nanos-microvm-lab/cold.log` ดู error (อาจต้องสลับ guest C→Go) |
| `ops image create failed` | kernel ยังไม่ถูกดึง → รัน `ops update` แล้วลองใหม่ |
| `restore ... load → ERR` | snapshot ไม่สมบูรณ์ → ดู `restore.log` + เช็ก `snap.mem` มีขนาด > 0 |

ถ้าติดตรงไหน ส่ง `cold.log` / `restore.log` มาให้ผู้ดูแล lab ได้เลย

---

## 📋 Checklist สำหรับผู้ทดสอบ (ติ๊กให้ครบ)

- [ ] เครื่องเป็น Linux + มี `/dev/kvm` + ใช้ sudo ได้
- [ ] คัดทั้งโฟลเดอร์ `nanos-microvm-lab/` ขึ้นเครื่องทดสอบแล้ว
- [ ] รัน `./lab6_nanos_microvm.sh` จบโดยขึ้น `✅ สำเร็จ`
- [ ] เห็น `COLD boot → service-ready` (ไม่ error)
- [ ] เห็น `GET / → 200 OK` + bytes > 0
- [ ] เห็น `RESTORE → service-ready` และ restore เร็วกว่า cold ชัดเจน
- [ ] เปิด `results.json` + `served_page.html` ดูได้จริง
- [ ] รัน `--clean` ล้างเรียบร้อยหลังเทสต์

---

> หมายเหตุ: lab นี้เป็น **guide ตัวอย่าง** — ปรับ mem / จำนวน restore / guest service
> ให้เหมาะกับสิ่งที่อยากวัดได้ตามสะดวก ตัวเลขทุกค่าวัดสดเสมอ ไม่มีของปลอม
