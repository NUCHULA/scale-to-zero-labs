// swift-tools-version:5.9
import PackageDescription

// Standalone demo ของหน้า Topology — คอมไพล์/รันได้โดยไม่ต้องมีทั้งแอป AI-SRE Monitor
//
// สำคัญ: มี TopologyTab.swift "ชุดเดียว" (ไฟล์ตัวอย่างที่ root ของโฟลเดอร์นี้)
//        package อ้างไฟล์นั้นตรง ๆ ผ่าน `sources` — ไม่มีสำเนาซ้ำ
//
//   swift build   → เช็กว่าคอมไพล์ผ่าน  → "Build complete!"
//   swift run     → เปิดหน้าต่างไดอะแกรมจริง (sample data)
// หรือเปิดโฟลเดอร์นี้ใน Xcode แล้วใช้ canvas preview (#Preview ใน demo/AppStateStub.swift)
let package = Package(
    name: "TopologyDemo",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "TopologyDemo",
            path: ".",
            exclude: ["README.md"],
            sources: [
                "TopologyTab.swift",       // ← ไฟล์ตัวอย่างชุดเดียว (อ้างตรงนี้)
                "demo/AppStateStub.swift", // ← stub + sample data + @main + #Preview
            ]
        )
    ]
)
