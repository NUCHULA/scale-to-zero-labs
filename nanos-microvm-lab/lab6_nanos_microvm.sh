#!/usr/bin/env bash
# ============================================================================
# Lab 6 (🐧 Linux + KVM) — Nanos unikernel บน Firecracker microVM (ของจริงล้วน)
# ----------------------------------------------------------------------------
# ทำอะไร (turnkey — ไม่มีอะไรก็ติดตั้งให้เอง แล้ววัดสดทุกตัวเลข ไม่มี hardcoded):
#   0) preflight + ติดตั้งของที่ขาด: firecracker · ops(Nanos) · gcc · kernel.img
#   1) build guest HTTP server (C, static) → ops image create = Nanos unikernel จริง
#   2) COLD boot บน Firecracker → จับเวลาจนเสิร์ฟ HTTP 200 (service-ready)
#   3) SNAPSHOT (Full) → วัดเวลา + ขนาดไฟล์จริง
#   4) RESTORE ×N → จับเวลา "ปลุกจาก snapshot" จนเสิร์ฟ 200 อีกครั้ง
#   5) ดึงหน้าเว็บจริงจาก guest มายืนยัน + สรุปผล (results.json)
#
# ต้องมี: Linux + /dev/kvm + sudo  (Mac ทำไม่ได้ — Firecracker ต้องการ KVM)
# วิธีรัน:
#   ./lab6_nanos_microvm.sh                 # cold + snapshot + restore ×5
#   ./lab6_nanos_microvm.sh --restores 20   # restore 20 รอบ (ดู median เสถียรขึ้น)
#   ./lab6_nanos_microvm.sh --mem 256       # เปลี่ยน RAM ที่จองให้ VM
#   ./lab6_nanos_microvm.sh --clean         # ลบ workdir + tap ทิ้ง (รีเซ็ต)
#
# PROD-SAFE: ใช้ host tap ชื่อเฉพาะ (nlabtap0) + subnet ของตัวเอง · ฆ่า FC เฉพาะ sock
#            ของตัวเองเท่านั้น — ไม่แตะ live-agent / vmnanos-controller บนเครื่องเดียวกัน
# ============================================================================
set -u
cd "$(dirname "$0")"
[ -f ./_common.sh ] && source ./_common.sh || {
  ts() { date '+%H:%M:%S'; }
  say()  { echo "[$(ts)] $*"; }
  note() { echo "[$(ts)]   · $*"; }
  warn() { echo "[$(ts)] ⚠️  $*" >&2; }
  step() { echo; echo "[$(ts)] ── ขั้น $1: ${*:2}"; }
}

# ---------------- config (แยกจาก prod) ----------------
LABDIR="$HOME/nanos-microvm-lab"          # workdir (image, snapshot, logs)
FILES="$(pwd)/lab6_files"
TAP="nlabtap0"; HOST_IP="172.16.0.1"; GUEST_IP="172.16.0.2"
IMG_NAME="nanoslab-httpd"
MEM=128; RESTORES=5

while [ $# -gt 0 ]; do
  case "$1" in
    --restores) RESTORES="$2"; shift 2;;
    --mem)      MEM="$2"; shift 2;;
    --clean)    sudo ip link del "$TAP" 2>/dev/null; rm -rf "$LABDIR"; echo "cleaned $LABDIR + tap $TAP"; exit 0;;
    *) warn "ไม่รู้จัก option: $1"; exit 1;;
  esac
done

mkdir -p "$LABDIR"
say "Lab 6 — Nanos unikernel บน Firecracker microVM (ของจริง · วัดสด)"
note "workdir = $LABDIR · guest = $GUEST_IP:8080 · mem = ${MEM}MiB · restores = $RESTORES"

# =================== ขั้น 0: preflight + auto-install ===================
step 0 "ตรวจสภาพแวดล้อม + ติดตั้งของที่ขาด"
[ "$(uname -s)" = "Linux" ] || { warn "ต้องเป็น Linux (เครื่องนี้=$(uname -s)). Firecracker ต้องการ KVM — รันบน VPS/Linux"; exit 1; }
[ -e /dev/kvm ] || { warn "ไม่มี /dev/kvm — เครื่องนี้ไม่มี hardware virtualization (รันใน VPS ที่เปิด nested virt / bare-metal)"; exit 1; }
say "✓ Linux + /dev/kvm"
sudo -n true 2>/dev/null && say "✓ sudo (passwordless)" || warn "sudo อาจถามรหัสผ่านระหว่างทาง (ปกติ)"

# gcc (build guest)
if ! command -v gcc >/dev/null 2>&1; then
  note "ไม่มี gcc → ติดตั้ง build-essential ..."
  sudo apt-get update -qq && sudo apt-get install -y -qq build-essential || { warn "ติดตั้ง gcc ไม่สำเร็จ"; exit 1; }
fi
say "✓ gcc $(gcc -dumpversion 2>/dev/null)"

# firecracker
FC_BIN="$(command -v firecracker || true)"
if [ -z "$FC_BIN" ]; then
  note "ไม่มี firecracker → ดาวน์โหลด release ล่าสุด ..."
  ARCH="$(uname -m)"   # x86_64 | aarch64
  VER="v1.15.1"
  URL="https://github.com/firecracker-microvm/firecracker/releases/download/${VER}/firecracker-${VER}-${ARCH}.tgz"
  TMP="$(mktemp -d)"
  if curl -fsSL "$URL" -o "$TMP/fc.tgz"; then
    tar -xzf "$TMP/fc.tgz" -C "$TMP"
    sudo install -m0755 "$TMP/release-${VER}-${ARCH}/firecracker-${VER}-${ARCH}" /usr/local/bin/firecracker
    FC_BIN="/usr/local/bin/firecracker"
  fi
  rm -rf "$TMP"
  [ -n "$FC_BIN" ] && [ -x "$FC_BIN" ] || { warn "ติดตั้ง firecracker ไม่สำเร็จ — ติดตั้งเองจาก github firecracker-microvm/releases"; exit 1; }
fi
say "✓ firecracker: $FC_BIN ($("$FC_BIN" --version 2>/dev/null | head -1))"

# ops (Nanos toolchain)
export PATH="$HOME/.ops/bin:$PATH"
if ! command -v ops >/dev/null 2>&1; then
  note "ไม่มี ops → ติดตั้งจาก ops.city ..."
  curl -fsSL https://ops.city/get.sh | sh || { warn "ติดตั้ง ops ไม่สำเร็จ"; exit 1; }
  export PATH="$HOME/.ops/bin:$PATH"
fi
command -v ops >/dev/null 2>&1 || { warn "ยังเรียก ops ไม่ได้ — เพิ่ม \$HOME/.ops/bin เข้า PATH"; exit 1; }
say "✓ ops: $(ops version 2>/dev/null | head -1)"

# nanos kernel.img (ops จะดึงมาเองตอน image create ครั้งแรก ถ้ายังไม่มี)
KERNEL="$(ls -d "$HOME"/.ops/0.1.*/kernel.img 2>/dev/null | sort -V | tail -1 || true)"
if [ -z "$KERNEL" ]; then
  note "ยังไม่มี Nanos kernel → สั่ง ops update ให้ดึง ..."
  ops update >/dev/null 2>&1 || true
  KERNEL="$(ls -d "$HOME"/.ops/0.1.*/kernel.img 2>/dev/null | sort -V | tail -1 || true)"
fi
[ -n "$KERNEL" ] && [ -f "$KERNEL" ] || { warn "หา Nanos kernel.img ไม่เจอ (ops จะสร้างตอน image create — ลองรันซ้ำ)"; }

# =================== ขั้น 1: build guest + Nanos image ===================
step 1 "build guest HTTP server (C, static) → Nanos unikernel image"
[ -f "$FILES/httpd.c" ] || { warn "ไม่พบ $FILES/httpd.c (ต้อง scp ทั้งโฟลเดอร์ lab6_files มาด้วย)"; exit 1; }
BUILD="$LABDIR/build"; mkdir -p "$BUILD"
gcc -static -O2 -o "$BUILD/svc" "$FILES/httpd.c" || { warn "compile guest ไม่สำเร็จ"; exit 1; }
say "✓ guest binary: $(du -h "$BUILD/svc" | cut -f1) (static ELF — รันบน Nanos ได้)"

cat > "$BUILD/index.html" <<'HTML'
<!doctype html><meta charset="utf-8"><title>Nanos × Firecracker — Lab 6</title>
<body style="font-family:system-ui;max-width:640px;margin:48px auto;line-height:1.6">
<h1>🐧 Hello from a Nanos unikernel</h1>
<p>หน้านี้เสิร์ฟสดจาก <b>Firecracker microVM</b> ที่บูต Nanos unikernel จริง
แล้วถูก snapshot ลงดิสก์และ <b>restore กลับมาในระดับมิลลิวินาที</b>.</p>
<p>นี่คือ scale-to-zero ตัวจริง: หลับ = คืนทรัพยากร, ตื่น = เร็วมาก.</p>
</body>
HTML
echo '{"Files":["index.html"]}' > "$BUILD/config.json"

# ops image create (สูตรเดียวกับ production live-agent: static IP + multi-file)
note "ops image create ... --ip-address $GUEST_IP (สร้าง unikernel ที่ network พร้อม)"
( cd "$BUILD" && HOME="$HOME" OPS_DIR="$HOME/.ops" PATH="$HOME/.ops/bin:$PATH" \
   ops image create svc -i "$IMG_NAME" --ip-address "$GUEST_IP" --gateway "$HOST_IP" \
   --netmask 255.255.255.0 -c config.json 2>&1 | tail -3 )
SRC="$HOME/.ops/images/$IMG_NAME"
[ -f "$SRC" ] || { warn "ops image create ล้มเหลว — ไม่พบ $SRC"; exit 1; }
IMG="$LABDIR/nanos.img"; cp "$SRC" "$IMG"; rm -f "$SRC"
KERNEL="${KERNEL:-$(ls -d "$HOME"/.ops/0.1.*/kernel.img | sort -V | tail -1)}"
say "✓ Nanos image: $IMG ($(du -h "$IMG" | cut -f1)) · kernel $KERNEL"

# =================== ขั้น 2–4: cold boot + snapshot + restore (วัดสด) ===================
step 2 "บูต + snapshot + restore บน Firecracker (driver วัดสดทุกตัวเลข)"
note "ทุกตัวเลขต่อจากนี้ = วัดรอบนี้จริง (host wall-clock → guest ตอบ HTTP 200)"
FC_BIN="$FC_BIN" sudo -E env "PATH=$PATH" python3 "$FILES/fc_driver.py" \
  --kernel "$KERNEL" --img "$IMG" --workdir "$LABDIR" \
  --tap "$TAP" --host-ip "$HOST_IP" --guest-ip "$GUEST_IP" \
  --mem "$MEM" --restores "$RESTORES"
RC=$?

step 3 "สรุป"
if [ $RC -eq 0 ]; then
  say "✅ สำเร็จ — ผลวัดสดอยู่ใน $LABDIR/results.json · หน้าเว็บที่ guest เสิร์ฟ: $LABDIR/served_page.html"
  note "บทเรียน: restore (ปลุกจาก snapshot) เร็วกว่า cold-boot มาก เพราะ 'ข้าม' การ boot ทั้งหมด"
  note "เลขทั้งหมดวัดสดบนเครื่องนี้ — ไม่มี hardcoded. รันซ้ำ/เพิ่ม --restores ได้เพื่อดูความเสถียร"
else
  warn "driver จบด้วย error (RC=$RC) — ดู log: $LABDIR/cold.log · $LABDIR/restore.log"
fi
exit $RC
