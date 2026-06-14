// ============================================================================
// AppStateStub.swift — stub ให้ TopologyTab.swift คอมไพล์ standalone ได้
// ----------------------------------------------------------------------------
// ในแอปจริง type พวกนี้มาจาก AppState.swift / Models.swift / RemoteHosts.swift
// (ต่อ MQTT + probe จริง). ไฟล์นี้คือ "เวอร์ชันจำลอง" ที่มีแค่ field ที่ TopologyTab
// ใช้จริง + ใส่ sample data ให้ไดอะแกรมมีของให้วาด → เปิด Xcode preview / swift run ได้เลย
//
// วิธีใช้ (รันจากโฟลเดอร์ topology ที่มี Package.swift):
//   • Xcode:     เปิดโฟลเดอร์ topology/ แล้วกด canvas preview (เห็นแอนิเมชันสด)
//   • เทอร์มินัล: swift build   (เช็กว่าคอมไพล์ผ่าน)
//                 swift run     (เปิดหน้าต่างจริง)
// NOTE: package อ้าง ../TopologyTab.swift (ตัวอย่างชุดเดียวที่ root) ผ่าน sources list ใน Package.swift
// ============================================================================

import SwiftUI
import AppKit

// ---- ค่าคงที่ที่ TopologyTab อ้างถึง ----
let PRIMARY_HOST_DISPLAY = "primary"

// ---- โมเดลข้อมูล (เฉพาะ field ที่ Topology ใช้) ----
struct GPUInfo {
    var name: String
}

struct LLMStats {
    var calls24h: Int?
    var tokensTotal24h: Int?
}

struct AISre {
    var llm: LLMStats?
    var incidentsOpen: Int?
}

struct StateSnapshot {
    var activeServiceCount: Int
    var totalServiceCount: Int
    var gpu: GPUInfo?
    var aiSre: AISre
}

struct RemoteHostState {
    var reachable: Bool
    var summary: String
    var latencyMs: Double?
    var healthStatus: String   // "ok" | "degraded" | ...
}

/// ในแอปจริงมี field เยอะ — Topology ใช้แค่ `.count` ของ array นี้
struct LLMCallRow {}

// ---- state กลาง (ObservableObject) — View observe ตัวนี้ ----
final class AppState: ObservableObject {
    @Published var snapshot: StateSnapshot?
    @Published var remoteHosts: [String: RemoteHostState] = [:]
    @Published var recentLLMCalls: [LLMCallRow] = []
    @Published var snapshotHistory: [(ts: Int, snap: StateSnapshot)] = []

    init() {}

    /// state ตัวอย่าง: ทุก host online → ไดอะแกรมมีเส้นวิ่ง + node เต้นครบ
    static var sample: AppState {
        let s = AppState()
        let snap = StateSnapshot(
            activeServiceCount: 42,
            totalServiceCount: 44,
            gpu: GPUInfo(name: "RTX PRO 4000"),
            aiSre: AISre(
                llm: LLMStats(calls24h: 128, tokensTotal24h: 1_900_000),
                incidentsOpen: 0
            )
        )
        s.snapshot = snap
        s.remoteHosts = [
            "nodeA": RemoteHostState(reachable: true, summary: "12 svc up",
                                       latencyMs: 3.2, healthStatus: "ok"),
            "nodeB": RemoteHostState(reachable: true, summary: "service ready",
                                   latencyMs: 5.1, healthStatus: "ok"),
        ]
        s.recentLLMCalls = Array(repeating: LLMCallRow(), count: 6)
        s.snapshotHistory = (0..<30).map { (ts: $0, snap: snap) }
        return s
    }

    /// state "ระบบมีปัญหา" — ลองสลับมาใช้เพื่อดูสีเปลี่ยน (แดง/เหลือง + เส้นบางเส้นดับ)
    static var degraded: AppState {
        let s = AppState()
        s.snapshot = StateSnapshot(
            activeServiceCount: 38, totalServiceCount: 44,
            gpu: GPUInfo(name: "RTX PRO 4000"),
            aiSre: AISre(llm: LLMStats(calls24h: 20, tokensTotal24h: 240_000),
                         incidentsOpen: 2)            // → node หลักเป็นสีแดง
        )
        s.remoteHosts = [
            "nodeA": RemoteHostState(reachable: true, summary: "degraded",
                                       latencyMs: 41, healthStatus: "degraded"),  // เหลือง
            "nodeB": RemoteHostState(reachable: false, summary: "unreachable",
                                   latencyMs: nil, healthStatus: "down"),          // แดง + เส้นดับ
        ]
        return s
    }
}

// ---- entry point ----
// • ปกติ (swift run)            → เปิดหน้าต่างจริง
// • swift run TopologyDemo --render out.png  → render เป็น PNG แบบ headless แล้วออก
//   (ใช้ ImageRenderer — ได้ภาพ deterministic ไม่ต้องเปิดหน้าต่าง/แคปจอ)
@main
struct Entry {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render"), i + 1 < args.count {
            renderPNG(to: args[i + 1])
            return
        }
        TopologyDemoApp.main()
    }

    @MainActor
    static func renderPNG(to path: String) {
        let view = TopologyTab(state: AppState.sample).frame(width: 1280, height: 760)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        guard let img = renderer.nsImage,
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write("render failed\n".data(using: .utf8)!)
            return
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("rendered → \(path)")
        } catch {
            FileHandle.standardError.write("write failed: \(error)\n".data(using: .utf8)!)
        }
    }
}

struct TopologyDemoApp: App {
    @StateObject private var state = AppState.sample
    var body: some Scene {
        WindowGroup("Topology Demo") {
            TopologyTab(state: state)
                .frame(minWidth: 960, minHeight: 640)
        }
    }
}

// ---- Xcode canvas preview ----
#Preview {
    TopologyTab(state: AppState.sample)
        .frame(width: 1000, height: 660)
}
