#!/usr/bin/env bash
# ============================================================================
# _common.sh — helper กลางของทุก lab (source ไฟล์นี้ ไม่ต้องรันตรง ๆ)
# ----------------------------------------------------------------------------
# ให้ 3 อย่าง:
#   1. timestamp ทุกบรรทัด  [HH:MM:SS.mmm]  → ผู้เรียน "เห็นเวลา" ตลอดการรัน
#   2. run_timed  → จับเวลา (ms) ของคำสั่งใด ๆ แล้วรายงาน ⏱
#   3. say/step/hr → พิมพ์คำอธิบายภาษาไทยให้อ่านง่ายเป็นจังหวะเดียวกันทุก lab
#
# หมายเหตุความแม่น: จับเวลาด้วย wall-clock ผ่าน perl/python (ความคลาดเคลื่อน
# ~10–30 ms จากการ spawn process) — พอสำหรับการ "เห็นสเกล" ของแต่ละขั้น
# ตัวเลขที่แม่นกว่าอยู่ในตัว harness/lab python ที่จับเวลาภายในตัวเอง
# ============================================================================

# ---- เวลา ------------------------------------------------------------------
ms_now() {  # เวลาปัจจุบันเป็น milliseconds (epoch)
  if command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes=time -e 'printf("%.0f", time()*1000)'
  else
    python3 -c 'import time; print(int(time.time()*1000))'
  fi
}
ts() {  # timestamp สำหรับ prefix บรรทัด เช่น [14:02:31.512]
  if command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes=time -MPOSIX -e '$t=time(); printf("[%s.%03d]", strftime("%H:%M:%S", localtime($t)), ($t-int($t))*1000)'
  else
    python3 -c 'import datetime; print(datetime.datetime.now().strftime("[%H:%M:%S.%f")[:-3]+"]", end="")'
  fi
}

# ---- การพิมพ์ ----------------------------------------------------------------
say()  { echo "$(ts) $*"; }                       # บรรทัดบรรยายทั่วไป (มี timestamp)
note() { echo "$(ts)    💡 $*"; }                  # คำอธิบายเสริม
warn() { echo "$(ts)    ⚠️  $*"; }                 # คำเตือน
hr()   { echo "──────────────────────────────────────────────────────────────"; }
step() {  # หัวข้อขั้นตอนใหญ่: step 1 "ตรวจเครื่องมือ"
  echo; hr; echo "$(ts) ▶ ขั้นที่ $1: $2"; hr
}

# ---- จับเวลา -----------------------------------------------------------------
# run_timed "ป้ายกำกับ" คำสั่ง...   → รันคำสั่ง แสดง output และรายงาน ⏱ ms
# คืนค่า exit code ของคำสั่งจริง และเก็บเวลาไว้ใน $LAST_MS
LAST_MS=0
run_timed() {
  local label="$1"; shift
  say "เริ่ม: $label"
  local t0 t1 rc
  t0=$(ms_now)
  "$@"
  rc=$?
  t1=$(ms_now)
  LAST_MS=$((t1 - t0))
  if [ $rc -eq 0 ]; then
    say "⏱  $label ใช้เวลา ${LAST_MS} ms"
  else
    warn "$label ล้มเหลว (exit $rc) หลังผ่านไป ${LAST_MS} ms"
  fi
  return $rc
}

# ---- ตรวจเครื่องมือ ------------------------------------------------------------
need() {  # need <คำสั่ง> "<วิธีติดตั้ง/คำแนะนำ>"  → ถ้าไม่มี จะเตือนแล้วคืน 1
  if command -v "$1" >/dev/null 2>&1; then
    say "✓ พบ $1 ($(command -v "$1"))"
    return 0
  else
    warn "ไม่พบ '$1' — $2"
    return 1
  fi
}

# ---- เฟรมเริ่ม/จบ lab ----------------------------------------------------------
LAB_T0=0
lab_begin() {  # lab_begin "ชื่อ lab" "ป้ายเครื่อง (💻/🐧)" "คำโปรย"
  LAB_T0=$(ms_now)
  echo; hr
  echo "$(ts) ████ $1  $2"
  echo "$(ts)      $3"
  hr
}
lab_end() {
  local total=$(( $(ms_now) - LAB_T0 ))
  echo; hr
  say "🏁 จบ lab — เวลารวมทั้งหมด $((total/1000)).$((total%1000)) วินาที"
  hr
}

# ---- กฎความซื่อตรง (ใช้ทุก lab) -------------------------------------------------
honesty_banner() {
  note "ตัวเลขที่วัดบนเครื่องคุณ = operating point ของ \"เครื่องคุณ + start-state ตอนนั้น\""
  note "ห้ามเอาไปเทียบตรง ๆ กับเลขอ้างอิงจาก session (วัดบน VPS คนละเครื่อง คนละเงื่อนไข)"
}
