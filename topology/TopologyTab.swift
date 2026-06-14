// ============================================================================
// TopologyTab.swift — ตัวอย่างจริงจากแอป "AI-SRE Monitor" (macOS, SwiftUI)
// แท็บ Topology: ไดอะแกรมระบบเคลื่อนไหว 60fps (TimelineView + Canvas + overlays)
// ----------------------------------------------------------------------------
// นี่คือ source โค้ดจริงของหน้านั้น คัดมาเป็น "ตัวอย่าง/ไกด์" เพื่อให้นำไปสร้างเองได้
// (ดู README.md ข้าง ๆ ไฟล์นี้ = อธิบาย flow + โครงสร้าง + วิธีดัดแปลง)
//
// ⚠️ ไฟล์นี้พึ่ง type ภายนอกของแอปจริง (ไม่ได้แนบมาในตัวอย่าง) ได้แก่:
//     • AppState           — ObservableObject ที่ถือ state ทั้งหมด (snapshot, remoteHosts, ...)
//     • StateSnapshot      — payload จาก MQTT (services, gpu, aiSre.llm, ...)
//     • RemoteHostState    — ผล probe ของ node อื่น ๆ (reachable, summary, latencyMs, ...)
//     • PRIMARY_HOST_DISPLAY — ค่าคงที่ชื่อ host หลัก (เช่น "primary")
//   ถ้าจะคอมไพล์เดี่ยว ให้ทำ mock type เหล่านี้ (ดูหัวข้อ "Data contract" ใน README)
//
// ที่มา: แท็บ Topology ของแอป AI-SRE Monitor (macOS SwiftUI) — คัดมาเป็นตัวอย่างเพื่อการสอน
// ============================================================================

import SwiftUI

// MARK: - Topology tab: animated system diagram (TimelineView + Canvas + SwiftUI overlays)

struct TopologyTab: View {
    @ObservedObject var state: AppState

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.07, blue: 0.12),
                             Color(red: 0.02, green: 0.03, blue: 0.06)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                AnimatedTopology(state: state, size: geo.size)
            }
        }
    }
}

/// 60fps animated topology — Canvas particles + SwiftUI overlays.
private struct AnimatedTopology: View {
    @ObservedObject var state: AppState
    let size: CGSize

    // Node positions (relative to canvas)
    private var positions: [String: CGPoint] {
        [
            "user":    CGPoint(x: size.width * 0.10, y: size.height * 0.55),
            "mac":     CGPoint(x: size.width * 0.43, y: size.height * 0.55),
            "vps":     CGPoint(x: size.width * 0.82, y: size.height * 0.55),
            "nodeA": CGPoint(x: size.width * 0.22, y: size.height * 0.22),
            "nodeB":     CGPoint(x: size.width * 0.22, y: size.height * 0.88),
        ]
    }

    private struct EdgeDef {
        let from: String
        let to: String
        let color: Color
        let label: String
        let speed: Double         // particles/sec
        let particleCount: Int
        let curveSign: CGFloat    // -1 / +1 — which side of midpoint to bow
        let active: Bool          // whether to draw particles
    }

    private var edges: [EdgeDef] {
        let hlActive = state.remoteHosts["nodeA"]?.reachable == true
        let mbpActive = state.remoteHosts["nodeB"]?.reachable == true
        let vpsActive = state.snapshot != nil
        return [
            EdgeDef(from: "user", to: "mac", color: .gray,
                    label: "interacts", speed: 0.25, particleCount: 2,
                    curveSign: 0, active: true),
            EdgeDef(from: "mac", to: "vps", color: Color(red: 0.45, green: 0.7, blue: 1.0),
                    label: "ssh + mosquitto_sub\nstate/* · monitor/* · llm/*",
                    speed: 0.7, particleCount: 6,
                    curveSign: -1, active: vpsActive),
            EdgeDef(from: "vps", to: "mac", color: Color(red: 0.35, green: 0.95, blue: 0.55),
                    label: "snapshot + llm/call/v1\n(retained MQTT)",
                    speed: 0.55, particleCount: 5,
                    curveSign: 1, active: vpsActive),
            EdgeDef(from: "mac", to: "nodeA", color: Color(red: 1.0, green: 0.65, blue: 0.2),
                    label: "HTTP /metrics\n(metrics exporter)",
                    speed: 0.4, particleCount: 3,
                    curveSign: 0, active: hlActive),
            EdgeDef(from: "mac", to: "nodeB", color: Color(red: 0.75, green: 0.5, blue: 1.0),
                    label: "HTTP /health\n(service API)",
                    speed: 0.4, particleCount: 3,
                    curveSign: 0, active: mbpActive),
        ]
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                // Edges + particles
                Canvas { ctx, _ in
                    for edge in edges {
                        guard let f = positions[edge.from], let to = positions[edge.to] else { continue }
                        drawEdge(ctx: ctx, from: f, to: to, edge: edge, t: t)
                    }
                }
                // Nodes (overlaid)
                ForEach(nodeViews, id: \.id) { node in
                    node.view
                        .position(node.position)
                }
                // Title + legend
                VStack(alignment: .leading) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Live System Topology")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("particles flow direction = data flow · animated 60 fps · status colors live")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                        legendBox
                    }
                    .padding(16)
                    Spacer()
                }
            }
        }
    }

    // MARK: Edge drawing

    private func drawEdge(ctx: GraphicsContext, from: CGPoint, to: CGPoint, edge: EdgeDef, t: TimeInterval) {
        // Bezier path with one control point pulled perpendicular to midpoint.
        let dx = to.x - from.x, dy = to.y - from.y
        let dist = sqrt(dx*dx + dy*dy)
        let pad: CGFloat = 80
        let p1 = CGPoint(x: from.x + dx * (pad / dist), y: from.y + dy * (pad / dist))
        let p2 = CGPoint(x: to.x - dx * (pad / dist), y: to.y - dy * (pad / dist))
        let mid = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
        let perp = CGPoint(x: -dy / dist, y: dx / dist)
        let curveAmount: CGFloat = dist * 0.10 * edge.curveSign
        let ctrl = CGPoint(x: mid.x + perp.x * curveAmount, y: mid.y + perp.y * curveAmount)

        // Track stroke (faint)
        var trackPath = Path()
        trackPath.move(to: p1)
        trackPath.addQuadCurve(to: p2, control: ctrl)
        ctx.stroke(trackPath, with: .color(edge.color.opacity(0.18)), style: StrokeStyle(lineWidth: 1.5))

        // Arrow head at p2
        let tangentAngle = atan2(p2.y - ctrl.y, p2.x - ctrl.x)
        let arrowSize: CGFloat = 9
        var arrow = Path()
        arrow.move(to: p2)
        arrow.addLine(to: CGPoint(
            x: p2.x - arrowSize * cos(tangentAngle - .pi/6),
            y: p2.y - arrowSize * sin(tangentAngle - .pi/6)))
        arrow.move(to: p2)
        arrow.addLine(to: CGPoint(
            x: p2.x - arrowSize * cos(tangentAngle + .pi/6),
            y: p2.y - arrowSize * sin(tangentAngle + .pi/6)))
        ctx.stroke(arrow, with: .color(edge.color.opacity(0.9)), style: StrokeStyle(lineWidth: 2, lineCap: .round))

        // Particles travelling along the curve (only when edge is active)
        if edge.active {
            for i in 0..<edge.particleCount {
                let offset = Double(i) / Double(edge.particleCount)
                let phase = ((t * edge.speed) + offset).truncatingRemainder(dividingBy: 1.0)
                let pos = bezierPoint(t: CGFloat(phase), p0: p1, p1: ctrl, p2: p2)
                // Fading head + glow
                let opacity = 0.4 + 0.5 * (1.0 - phase)
                let r: CGFloat = 4.5
                let dot = Path(ellipseIn: CGRect(x: pos.x - r, y: pos.y - r, width: r*2, height: r*2))
                ctx.fill(dot, with: .color(edge.color.opacity(opacity)))
                let halo = Path(ellipseIn: CGRect(x: pos.x - r*2, y: pos.y - r*2, width: r*4, height: r*4))
                ctx.fill(halo, with: .color(edge.color.opacity(opacity * 0.18)))
            }
        }

        // Label at curve midpoint
        let lt = CGFloat(0.5)
        let labelPos = bezierPoint(t: lt, p0: p1, p1: ctrl, p2: p2)
        let labelOffset = CGPoint(x: perp.x * curveAmount * 0.6 + (edge.curveSign == 0 ? 0 : 0),
                                  y: perp.y * curveAmount * 0.6 - 10)
        let text = Text(edge.label)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(edge.color.opacity(0.95))
        ctx.draw(text, at: CGPoint(x: labelPos.x + labelOffset.x, y: labelPos.y + labelOffset.y), anchor: .center)
    }

    private func bezierPoint(t: CGFloat, p0: CGPoint, p1: CGPoint, p2: CGPoint) -> CGPoint {
        let u = 1.0 - t
        let x = u * u * p0.x + 2 * u * t * p1.x + t * t * p2.x
        let y = u * u * p0.y + 2 * u * t * p1.y + t * t * p2.y
        return CGPoint(x: x, y: y)
    }

    // MARK: Nodes

    private struct NodeRender {
        let id: String
        let view: AnyView
        let position: CGPoint
    }

    private var nodeViews: [NodeRender] {
        var out: [NodeRender] = []
        for (key, pos) in positions {
            switch key {
            case "user":
                out.append(NodeRender(id: key, view: AnyView(userNode), position: pos))
            case "mac":
                out.append(NodeRender(id: key, view: AnyView(macNode), position: pos))
            case "vps":
                out.append(NodeRender(id: key, view: AnyView(vpsNode), position: pos))
            case "nodeA":
                out.append(NodeRender(id: key, view: AnyView(nodeANode), position: pos))
            case "nodeB":
                out.append(NodeRender(id: key, view: AnyView(nodeBNode), position: pos))
            default: break
            }
        }
        return out
    }

    private var userNode: some View {
        NodeCard(
            icon: "person.crop.circle.fill", title: "You", subtitle: "user",
            lines: ["macOS host", "menubar 🟢"],
            tint: Color(red: 0.6, green: 0.6, blue: 0.65),
            width: 140, pulse: false
        )
    }

    private var macNode: some View {
        let connected = state.snapshot != nil
        return NodeCard(
            icon: "laptopcomputer", title: "Mac", subtitle: "monitor.app",
            lines: [
                "SwiftUI · MenuBarExtra",
                "SQLite · Swift Charts",
                "\(state.recentLLMCalls.count) live · \(state.snapshotHistory.count) snaps",
            ],
            tint: Color(red: 0.45, green: 0.7, blue: 1.0),
            width: 220,
            pulse: connected
        )
    }

    private var vpsNode: some View {
        let s = state.snapshot
        let llm = s?.aiSre.llm
        let lines: [String] = [
            "LLM runtime · model",
            "MQTT · DB · logs · metrics",
            "agent + healthcheck",
            s.map { "\($0.activeServiceCount)/\($0.totalServiceCount) svc · \($0.aiSre.incidentsOpen ?? 0) open" } ?? "—",
            llm.map { "LLM 24h: \($0.calls24h ?? 0) calls · \(formatK($0.tokensTotal24h ?? 0)) tok" } ?? "—",
        ]
        return NodeCard(
            icon: "cloud.fill", title: PRIMARY_HOST_DISPLAY,
            subtitle: "Cloud · \(s?.gpu?.name ?? "GPU?")",
            lines: lines,
            tint: primaryStatusColor,
            width: 270, pulse: s != nil
        )
    }

    private var nodeANode: some View {
        let rs = state.remoteHosts["nodeA"]
        let lines: [String] = [
            "container host",
            "vector-db · DB · cache · logs",
            "admin · metrics · CI",
            rs.map { "\($0.summary)" } ?? "probing…",
            rs.flatMap { $0.latencyMs }.map { String(format: "latency %.0f ms", $0) } ?? "",
        ].filter { !$0.isEmpty }
        let color = remoteColor(rs)
        return NodeCard(
            icon: "server.rack", title: "Node A", subtitle: "10.0.0.11",
            lines: lines, tint: color, width: 230,
            pulse: rs?.reachable == true
        )
    }

    private var nodeBNode: some View {
        let rs = state.remoteHosts["nodeB"]
        let lines: [String] = [
            "embedding svc :8100",
            "dense + sparse + late-interaction",
            rs.map { "\($0.summary)" } ?? "probing…",
            rs.flatMap { $0.latencyMs }.map { String(format: "latency %.0f ms", $0) } ?? "",
        ].filter { !$0.isEmpty }
        let color = remoteColor(rs)
        return NodeCard(
            icon: "macbook", title: "Node B", subtitle: "10.0.0.12",
            lines: lines, tint: color, width: 210,
            pulse: rs?.reachable == true
        )
    }

    private var primaryStatusColor: Color {
        guard let s = state.snapshot else { return Color.gray }
        if let open = s.aiSre.incidentsOpen, open > 0 { return Color(red: 1.0, green: 0.35, blue: 0.35) }
        if s.activeServiceCount < s.totalServiceCount { return Color(red: 1.0, green: 0.8, blue: 0.3) }
        return Color(red: 0.35, green: 0.95, blue: 0.55)
    }

    private func remoteColor(_ s: RemoteHostState?) -> Color {
        guard let s else { return .gray }
        if !s.reachable { return Color(red: 1.0, green: 0.35, blue: 0.35) }
        if s.healthStatus == "degraded" { return Color(red: 1.0, green: 0.65, blue: 0.2) }
        return Color(red: 0.35, green: 0.95, blue: 0.55)
    }

    private func formatK(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n)/1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n)/1_000) }
        return "\(n)"
    }

    private var legendBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            legendRow(color: Color(red: 0.45, green: 0.7, blue: 1.0), label: "Mac → VPS (subscribe)")
            legendRow(color: Color(red: 0.35, green: 0.95, blue: 0.55), label: "VPS → Mac (events)")
            legendRow(color: Color(red: 1.0, green: 0.65, blue: 0.2), label: "Mac → Node A (HTTP)")
            legendRow(color: Color(red: 0.75, green: 0.5, blue: 1.0), label: "Mac → Node B (HTTP)")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.15)))
    }

    private func legendRow(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 10)).foregroundStyle(.white.opacity(0.8))
        }
    }
}

/// A glowing animated node card. Uses a pulsing halo when `pulse` is true.
private struct NodeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let lines: [String]
    let tint: Color
    let width: CGFloat
    let pulse: Bool

    @State private var pulsePhase: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ZStack {
                    if pulse {
                        Circle()
                            .fill(tint.opacity(0.35))
                            .frame(width: 36, height: 36)
                            .scaleEffect(1.0 + pulsePhase * 0.6)
                            .opacity(Double(1.0 - pulsePhase))
                    }
                    Circle()
                        .fill(tint.opacity(0.18))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .foregroundStyle(tint)
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    Text(subtitle).font(.system(size: 9)).foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Circle().fill(tint).frame(width: 8, height: 8)
                    .shadow(color: tint, radius: 4)
            }
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            ForEach(lines.indices, id: \.self) { i in
                Text(lines[i])
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(10)
        .frame(width: width, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    LinearGradient(colors: [tint.opacity(0.7), tint.opacity(0.25)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.2)
        )
        .shadow(color: tint.opacity(0.4), radius: 12, x: 0, y: 0)
        .onAppear {
            guard pulse else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                pulsePhase = 1.0
            }
        }
    }
}
