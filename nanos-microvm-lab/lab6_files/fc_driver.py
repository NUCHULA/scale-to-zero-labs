#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
fc_driver.py — Lab 6 measurement core (รันด้วย sudo)
============================================================================
บูต Nanos unikernel ตัวจริงบน Firecracker microVM แล้ว "วัดสดทุกตัวเลข":
  1) COLD boot   : InstanceStart → จับ wall-clock จนกว่า guest ตอบ HTTP 200 (service-ready)
  2) SNAPSHOT    : pause + Full snapshot (เก็บ state+mem) → วัดเวลา create + ขนาดไฟล์จริง
  3) RESTORE ×N  : โหลด snapshot กลับ (resume) → จับ wall-clock จนตอบ 200 อีกครั้ง

basis เดียวกับ paper: host wall-clock → service-ready (HTTP 200 ผ่าน network).
ไม่มีเลข hardcoded — print เฉพาะค่าที่วัดได้รอบนี้ (+ ขนาด/คอนเทนต์จริง).

PROD-SAFE:
  • ใช้ host tap ชื่อเฉพาะ (default nlabtap0) + subnet ของตัวเอง → ไม่มี netns/iptables ไปยุ่ง prod
  • kill FC เฉพาะ "ตัวเราเอง" ด้วย exact api-sock path — ไม่เคย pkill firecracker (จะฆ่า live-agent/controller)
"""

import argparse
import json
import os
import socket
import subprocess
import sys
import time


def sh(*a):
    return subprocess.run(["sudo", *a], capture_output=True, text=True)


def api(sock, method, route, body=None, timeout=8.0):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    deadline = time.perf_counter() + timeout
    while True:
        try:
            s.connect(sock)
            break
        except OSError:
            if time.perf_counter() > deadline:
                s.close()
                return "ERR no-socket"
            time.sleep(0.005)
    try:
        s.settimeout(timeout)
        data = json.dumps(body) if body is not None else ""
        s.sendall(
            (
                f"{method} {route} HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\n"
                f"Content-Length: {len(data)}\r\n\r\n{data}"
            ).encode()
        )
        return s.recv(65536).decode(errors="replace").split("\r\n")[0]
    except OSError:
        return "ERR timeout"
    finally:
        s.close()


def ok2xx(line):
    return ("204" in line) or ("200" in line)


def wait_sock(sock, timeout=8):
    end = time.perf_counter() + timeout
    while time.perf_counter() < end:
        try:
            c = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            c.connect(sock)
            c.close()
            return True
        except OSError:
            time.sleep(0.005)
    return False


def probe(addr, t0, path=b"/healthz", timeout=25):
    """รอจน guest ตอบ 200 จริง — คืน ms นับจาก t0 (service-ready latency)."""
    end = time.perf_counter() + timeout
    while time.perf_counter() < end:
        try:
            c = socket.create_connection(addr, timeout=0.5)
            c.sendall(b"GET " + path + b" HTTP/1.0\r\n\r\n")
            r = c.recv(64)
            c.close()
            if b"200" in r:
                return (time.perf_counter() - t0) * 1000
        except OSError:
            time.sleep(0.02)
    return None


def fetch(addr, path=b"/", timeout=5):
    """ดึงหน้าเว็บจริงจาก guest → คืน (status_line, body_bytes)."""
    try:
        c = socket.create_connection(addr, timeout=timeout)
        c.sendall(b"GET " + path + b" HTTP/1.0\r\n\r\n")
        buf = b""
        while True:
            chunk = c.recv(4096)
            if not chunk:
                break
            buf += chunk
        c.close()
        head, _, body = buf.partition(b"\r\n\r\n")
        status = head.split(b"\r\n")[0].decode(errors="replace")
        return status, body
    except OSError as e:
        return f"ERR {e}", b""


def tap_up(tap, host_ip):
    sh("ip", "tuntap", "add", tap, "mode", "tap")  # idempotent: ล้มก็ข้าม
    sh("ip", "addr", "add", f"{host_ip}/24", "dev", tap)
    sh("ip", "link", "set", tap, "up")


def tap_down(tap):
    sh("ip", "link", "del", tap)


def fc_start(sock, log):
    if os.path.exists(sock):
        sh("rm", "-f", sock)
    return subprocess.Popen(
        ["sudo", FC, "--api-sock", sock],
        stdout=open(log, "w"),
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )


def fc_kill(p, sock):
    try:
        if p:
            p.kill()
            p.wait(timeout=3)
    except Exception:
        pass
    sh("pkill", "-9", "-f", sock)  # exact sock เท่านั้น — prod-safe


def stats(xs):
    xs = sorted(x for x in xs if x is not None)
    if not xs:
        return None
    n = len(xs)
    mean = sum(xs) / n
    sd = (sum((x - mean) ** 2 for x in xs) / (n - 1)) ** 0.5 if n > 1 else 0.0
    return {
        "n": n,
        "median": round(xs[n // 2], 1),
        "mean": round(mean, 1),
        "sd": round(sd, 1),
        "min": round(xs[0], 1),
        "max": round(xs[-1], 1),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kernel", required=True)
    ap.add_argument("--img", required=True)
    ap.add_argument("--workdir", required=True)
    ap.add_argument("--tap", default="nlabtap0")
    ap.add_argument("--host-ip", default="172.16.0.1")
    ap.add_argument("--guest-ip", default="172.16.0.2")
    ap.add_argument("--mac", default="06:00:AC:10:00:02")
    ap.add_argument("--mem", type=int, default=128)
    ap.add_argument("--restores", type=int, default=5)
    a = ap.parse_args()

    global FC
    FC = os.environ.get("FC_BIN", "firecracker")

    sock = a.workdir + "/fc.sock"
    state = a.workdir + "/snap.state"
    memf = a.workdir + "/snap.mem"
    clog = a.workdir + "/cold.log"
    rlog = a.workdir + "/restore.log"
    addr = (a.guest_ip, 8080)
    os.makedirs(a.workdir, exist_ok=True)

    print(
        f"[driver] tap {a.tap} ({a.host_ip}/24) → guest {a.guest_ip}:8080  mem={a.mem}MiB",
        flush=True,
    )
    tap_up(a.tap, a.host_ip)

    result = {"mem_mib": a.mem, "guest": a.guest_ip}

    # ---------- 1) COLD BOOT ----------
    p = fc_start(sock, clog)
    try:
        if not wait_sock(sock):
            print("[driver] FATAL: FC api-sock ไม่ขึ้น", flush=True)
            sys.exit(1)
        for route, payload in [
            (
                "/boot-source",
                {"kernel_image_path": a.kernel, "boot_args": "console=ttyS0"},
            ),
            ("/machine-config", {"vcpu_count": 1, "mem_size_mib": a.mem}),
            (
                "/drives/rootfs",
                {
                    "drive_id": "rootfs",
                    "path_on_host": a.img,
                    "is_root_device": True,
                    "is_read_only": False,
                },
            ),
            (
                "/network-interfaces/eth0",
                {"iface_id": "eth0", "guest_mac": a.mac, "host_dev_name": a.tap},
            ),
        ]:
            r = api(sock, "PUT", route, payload)
            if not ok2xx(r):
                print(f"[driver] FATAL: PUT {route} → {r}", flush=True)
                sys.exit(1)
        t0 = time.perf_counter()
        if not ok2xx(api(sock, "PUT", "/actions", {"action_type": "InstanceStart"})):
            print("[driver] FATAL: InstanceStart", flush=True)
            sys.exit(1)
        boot_ms = probe(addr, t0, timeout=30)
        if boot_ms is None:
            print(f"[driver] FATAL: guest ไม่ตอบ 200 ใน 30s — ดู {clog}", flush=True)
            sys.exit(1)
        result["cold_boot_ms"] = round(boot_ms, 1)
        print(f"[driver] COLD boot → service-ready {boot_ms:.1f} ms", flush=True)

        # ดึงหน้าเว็บจริงมายืนยันว่าเสิร์ฟของจริง
        status, body = fetch(addr, b"/")
        result["served_status"] = status
        result["served_bytes"] = len(body)
        open(a.workdir + "/served_page.html", "wb").write(body)
        print(
            f"[driver] GET / → {status} · {len(body)} bytes (เซฟ {a.workdir}/served_page.html)",
            flush=True,
        )

        # ---------- 2) SNAPSHOT ----------
        api(sock, "PATCH", "/vm", {"state": "Paused"})
        for f in (state, memf):
            if os.path.exists(f):
                sh("rm", "-f", f)
        tc = time.perf_counter()
        r = api(
            sock,
            "PUT",
            "/snapshot/create",
            {"snapshot_type": "Full", "snapshot_path": state, "mem_file_path": memf},
        )
        create_ms = (time.perf_counter() - tc) * 1000
        if not ok2xx(r):
            print(f"[driver] FATAL: snapshot/create → {r}", flush=True)
            sys.exit(1)
        result["snap_create_ms"] = round(create_ms, 1)
        result["snap_mem_mb"] = round(os.path.getsize(memf) / 1048576, 1)
        result["snap_state_kb"] = round(os.path.getsize(state) / 1024, 1)
        print(
            f"[driver] SNAPSHOT created {create_ms:.1f} ms · mem-file {result['snap_mem_mb']} MB · "
            f"state {result['snap_state_kb']} KB",
            flush=True,
        )
    finally:
        fc_kill(p, sock)

    # ---------- 3) RESTORE ×N ----------
    wakes = []
    for i in range(a.restores):
        p = fc_start(sock, rlog)
        try:
            if not wait_sock(sock):
                wakes.append(None)
                continue
            t0 = time.perf_counter()
            r = api(
                sock,
                "PUT",
                "/snapshot/load",
                {
                    "snapshot_path": state,
                    "mem_file_path": memf,
                    "resume_vm": True,
                    "network_overrides": [{"iface_id": "eth0", "host_dev_name": a.tap}],
                },
            )
            if not ok2xx(r):
                print(f"[driver] restore {i + 1}: load → {r}", flush=True)
                wakes.append(None)
                continue
            w = probe(addr, t0, timeout=15)
            wakes.append(w)
            print(
                f"[driver] RESTORE {i + 1}/{a.restores} → service-ready {w} ms",
                flush=True,
            )
        finally:
            fc_kill(p, sock)

    result["restore_wake"] = stats(wakes)

    # cleanup tap (prod ไม่ถูกแตะ)
    tap_down(a.tap)

    open(a.workdir + "/results.json", "w").write(json.dumps(result, indent=2))
    print("\n===== RESULTS (วัดสดรอบนี้ทั้งหมด) =====", flush=True)
    print(json.dumps(result, indent=2, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
