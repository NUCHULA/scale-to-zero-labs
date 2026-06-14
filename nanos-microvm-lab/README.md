# Lab 6 — Nanos unikernel บน Firecracker microVM (ของจริงล้วน · turnkey)

แล็บนี้ **ติดตั้งจริง บูตจริง วัดจริง** — ไม่มี simulation ไม่มีตัวเลข hardcoded
ทุกตัวเลขที่ออกมา = วัดสดบนเครื่องที่รัน ณ ตอนนั้น

> สร้าง Nanos unikernel จาก HTTP server เล็ก ๆ → บูตบน Firecracker microVM →
> snapshot ลงดิสก์ → **restore กลับมาในระดับมิลลิวินาที** = scale-to-zero ตัวจริง

---

## ต้องมีอะไร

| สิ่งที่ต้องมี | หมายเหตุ |
|--------------|----------|
| **Linux + `/dev/kvm`** | Firecracker ต้องการ KVM — **macOS รันไม่ได้** ใช้ VPS / bare-metal / Linux ที่เปิด nested virt |
| **sudo** | ใช้สร้าง tap + รัน Firecracker (ถ้า passwordless จะรันลื่นไม่มีสะดุด) |
| อินเทอร์เน็ต (ครั้งแรก) | ไว้ให้สคริปต์ดาวน์โหลดของที่ขาด (ดูหัวข้อถัดไป) |

ของที่เหลือ **สคริปต์ติดตั้งให้เอง** ถ้าไม่มี — ไม่ต้องเตรียมล่วงหน้า

---

## รันยังไง (turnkey — คำสั่งเดียวจบ)

```bash
cd nanos-microvm-lab
./lab6_nanos_microvm.sh
```

แค่นี้ ถ้าเครื่องเปล่า สคริปต์จะ:

1. ตรวจ Linux + `/dev/kvm` + sudo
2. **ติดตั้งให้อัตโนมัติถ้าขาด** → `gcc` (build-essential) · `firecracker` (ดาวน์โหลด release) · `ops` (Nanos toolchain จาก ops.city) · Nanos `kernel.img`
3. build guest HTTP server (C, static) → `ops image create` = Nanos unikernel จริง
4. บูตบน Firecracker → จับเวลาจนเสิร์ฟ **HTTP 200** (service-ready)
5. snapshot (Full) → วัดเวลา create + ขนาดไฟล์จริง
6. restore กลับ ×N → จับเวลา "ปลุกจาก snapshot" จนเสิร์ฟ 200 อีกครั้ง
7. ดึงหน้าเว็บจริงจาก guest มายืนยัน + เซฟผลลง `results.json`

### ออปชัน

```bash
./lab6_nanos_microvm.sh --restores 20   # restore 20 รอบ (median เสถียรขึ้น) · default 5
./lab6_nanos_microvm.sh --mem 256       # เปลี่ยน RAM ที่จองให้ VM · default 128 MiB
./lab6_nanos_microvm.sh --clean         # ลบ workdir + tap ทิ้ง (รีเซ็ตให้สะอาด)
```

---

## ผลที่ได้ (ทุกค่า = วัดสด ไม่มี hardcoded)

หลังรัน ดูได้ที่ `~/nanos-microvm-lab/` (workdir):

| ไฟล์ | คืออะไร |
|------|---------|
| `results.json` | ผลวัดทั้งหมด: `cold_boot_ms` · `snap_create_ms` · `snap_mem_mb` · `restore_wake` (median/min/max/sd) |
| `served_page.html` | หน้าเว็บจริงที่ guest unikernel เสิร์ฟกลับมา (พิสูจน์ว่าเสิร์ฟจริง) |
| `cold.log` / `restore.log` | log ของ Firecracker ตอน cold-boot / restore (ไว้ debug) |
| `nanos.img` | Nanos unikernel image ที่ build ได้ |
| `snap.state` / `snap.mem` | snapshot (สถานะ VM + หน่วยความจำ) |

สิ่งที่จะได้เห็น: **restore เร็วกว่า cold-boot หลายเท่า** เพราะ restore "ข้าม" การ boot ทั้งหมด —
โหลดสถานะหน่วยความจำที่เคย boot ไว้กลับมาตรง ๆ นี่คือ fast-path ของ scale-to-zero

> ⚠️ ตัวเลขขึ้นกับเครื่อง + โหลด ณ ขณะนั้น — เป็น "operating point ของเครื่องคุณ"
> อย่าเอาไปเทียบข้ามเครื่อง/ข้าม start-state แบบไม่ตรึงเงื่อนไข

---

## โครงสร้างไฟล์

```
nanos-microvm-lab/
├── README.md                  ← ไฟล์นี้
├── lab6_nanos_microvm.sh      ← orchestrator (preflight + install + build + run)
├── _common.sh                 ← helper: timestamp / จับเวลา / บรรยายไทย
└── lab6_files/
    ├── httpd.c                ← guest HTTP server (C, static — เล็กสุดที่บูต Nanos ได้)
    └── fc_driver.py           ← วัดสด: cold-boot · snapshot · restore (เรียก Firecracker API จริง)
```

---

## ปลอดภัยกับ production ไหม (prod-safe)

ออกแบบมาให้รันบนเครื่องเดียวกับ service อื่นได้โดยไม่ชนกัน:

- ใช้ **host tap ชื่อเฉพาะ** (`nlabtap0`) + subnet ของตัวเอง → ไม่มี netns/iptables ไปยุ่งของเดิม
- ฆ่า Firecracker **เฉพาะตัวเราเอง** ด้วย exact api-sock path — **ไม่เคย `pkill firecracker`**
  (ถ้า pkill จะไปฆ่า service อื่นที่ใช้ Firecracker บนเครื่องเดียวกัน)
- ทุกอย่างเก็บใน workdir แยก (`~/nanos-microvm-lab/`) — `--clean` ลบทิ้งได้หมด

---

## สถานะการทดสอบ

- ✅ เขียนครบ + syntax ผ่าน (bash + python) + อัปโหลดขึ้น VPS แล้ว (`~/vmnanos-labs/`)
- ⏳ **ยังไม่ได้รัน end-to-end** บน VPS (ติด auto-mode classifier ที่กันการรัน auto-install/microVM
  บน host production) → รอรันจริงครั้งแรกเพื่อ capture เลขสด แล้วจะเติมตัวอย่างผลในไฟล์นี้

รันครั้งแรกบน VPS:

```bash
ssh user@<host> 'cd ~/vmnanos-labs && ./lab6_nanos_microvm.sh --restores 3'
```

---

## แก้ปัญหาที่อาจเจอ

| อาการ | สาเหตุ / วิธีแก้ |
|-------|----------------|
| `ต้องเป็น Linux` / `ไม่มี /dev/kvm` | รันบน Mac/เครื่องไม่มี KVM — ย้ายไป Linux ที่เปิด virtualization |
| guest ไม่ตอบ 200 (ดู `cold.log`) | C-static binary อาจไม่เข้ากับ Nanos บางรุ่น → สลับ guest เป็น **Go** (ops happy-path) แล้ว build ใหม่ |
| `ops image create failed` | kernel ยังไม่ถูกดึง — รัน `ops update` แล้วลองใหม่ |
| restore ล้มเหลว | ตรวจว่า snapshot ถูกสร้างสำเร็จก่อน (`snap.mem` มีขนาด > 0) · ดู `restore.log` |
| sudo ถามรหัสทุกขั้น | ปกติ — หรือ config passwordless sudo ให้ user ที่รัน |

> หมายเหตุ guest: ใช้ C + gcc เพราะ gcc มีแทบทุกเครื่อง (ไม่ต้องโหลด toolchain ใหญ่)
> ถ้าเจอปัญหากับ Nanos รุ่นใด ๆ ทางสำรองที่ชัวร์สุดคือเปลี่ยน guest เป็น Go
> (ops + Go เป็น happy-path ของ Nanos) — แจ้งได้ เดี๋ยวสลับให้แบบยังคง turnkey
