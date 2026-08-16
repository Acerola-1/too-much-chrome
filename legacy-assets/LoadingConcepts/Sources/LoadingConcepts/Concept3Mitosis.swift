import SwiftUI

// MARK: 概念③ Chromium 有丝分裂
// 原子徽标落场 → 按代际指数分裂（1→2→4→8→16→28，黄金角螺旋簇）→
// Tauri/Wails 侧芽 → 按槽位离中心距离分层散开归位。
// 图标住在网格槽位里，用 offset 把自己挪到簇位置——与 HTML 版同一套几何。

struct ConceptMitosisView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase: Equatable {
        case hidden
        case cluster(CGSize)
        case landed
    }

    private enum EmblemPhase {
        case hidden, visible, squash, stretch, gone
    }

    @State private var phases: [Phase] = Array(repeating: .hidden, count: SampleData.count)
    @State private var emblemPhase: EmblemPhase = .hidden
    @State private var captured = 0
    @State private var capturedMB = 0
    @State private var toast = false

    var body: some View {
        ConceptFrame(info: .mitosis, captured: captured, capturedMB: capturedMB) {
            ZStack {
                IconGrid { app in
                    IconCell(app: app)
                        .offset(offset(for: app.id))
                        .scaleEffect(scale(for: app.id))
                        .opacity(opacity(for: app.id))
                }
                .frame(width: GridGeom.width, height: GridGeom.height)

                if emblemPhase != .gone {
                    AtomView()
                        .scaleEffect(
                            x: emblemPhase == .squash ? 1.18 : (emblemPhase == .stretch ? 0.95 : 1),
                            y: emblemPhase == .squash ? 0.82 : (emblemPhase == .stretch ? 1.06 : 1)
                        )
                        .opacity(emblemPhase == .hidden ? 0 : 1)
                        .scaleEffect(emblemPhase == .gone ? 0.1 : 1)
                }

                if toast {
                    ToastView(text: "Chromium × 28 · 指数级增殖完毕")
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .clipped()
        }
        .task { await run() }
    }

    // MARK: 槽位 ↔ 簇位置换算

    private func offset(for i: Int) -> CGSize {
        let slot = GridGeom.slotOffset(i)
        switch phases[i] {
        case .hidden:
            // 出生在网格中心：相对槽位的反向偏移
            return CGSize(width: -slot.width, height: -slot.height)
        case .cluster(let cluster):
            return CGSize(width: cluster.width - slot.width, height: cluster.height - slot.height)
        case .landed:
            return .zero
        }
    }

    private func scale(for i: Int) -> CGFloat {
        phases[i] == .hidden ? 0.15 : 1
    }

    private func opacity(for i: Int) -> Double {
        phases[i] == .hidden ? 0 : 1
    }

    /// 黄金角螺旋：簇随数量自然向外生长
    private func spiral(_ i: Int) -> CGSize {
        let r = 16.0 * sqrt(Double(i + 1))
        let theta = Double(i) * 2.399963
        return CGSize(width: r * cos(theta), height: r * sin(theta))
    }

    // MARK: 时间线

    private func run() async {
        if reduceMotion {
            phases = Array(repeating: .landed, count: SampleData.count)
            captured = SampleData.count
            capturedMB = SampleData.sumMB
            return
        }

        do {
            // 原子徽标落场
            withAnimation(.spring(response: 0.24, dampingFraction: 0.68)) { emblemPhase = .visible }
            try await Task.sleep(for: .milliseconds(330))

            // 分裂前的挤压预兆（两段果冻）
            withAnimation(.easeInOut(duration: 0.07)) { emblemPhase = .squash }
            try await Task.sleep(for: .milliseconds(70))
            withAnimation(.easeInOut(duration: 0.07)) { emblemPhase = .stretch }
            try await Task.sleep(for: .milliseconds(80))

            // 指数分裂：1→2→4→8→16→28（Electron 占前 28 个）
            let generations: [(count: Int, time: Int)] = [
                (1, 480), (2, 585), (4, 690), (8, 790), (16, 885), (28, 975)
            ]
            var previous = 0
            var clock = 0
            for gen in generations {
                try await nap(until: gen.time, clock: &clock)
                if gen.count == 1 {
                    withAnimation(.easeIn(duration: 0.15)) { emblemPhase = .gone }
                }
                spawn(previous..<gen.count)
                previous = gen.count
            }

            // Tauri / Wails 侧芽（延续同一螺旋，天然落在簇外缘）
            try await nap(until: 1065, clock: &clock)
            spawn(28..<SampleData.count)

            // 散开：按槽位离中心距离分层波次飞向网格
            try await nap(until: 1180, clock: &clock)
            let order = (0..<SampleData.count)
                .map { ($0, hypot(GridGeom.slotOffset($0).width, GridGeom.slotOffset($0).height)) }
                .sorted { $0.1 < $1.1 }
            for (_, item) in order.enumerated() {
                try await Task.sleep(for: .milliseconds(12))
                let i = item.0
                withAnimation(.spring(response: 0.34, dampingFraction: 0.75)) {
                    phases[i] = .landed
                }
                Task {
                    try? await Task.sleep(for: .milliseconds(360))
                    captured += 1
                    capturedMB += SampleData.apps[i].totalMB
                }
            }

            try await Task.sleep(for: .milliseconds(620))
            withAnimation(.easeOut(duration: 0.2)) { toast = true }
            try await Task.sleep(for: .milliseconds(1100))
            withAnimation(.easeIn(duration: 0.25)) { toast = false }
        } catch {
            // 任务取消（切换 / 重播）
        }
    }

    private func spawn(_ range: Range<Int>) {
        for i in range {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.72)) {
                phases[i] = .cluster(spiral(i))
            }
        }
    }

    private func nap(until target: Int, clock: inout Int) async throws {
        if target > clock {
            try await Task.sleep(for: .milliseconds(target - clock))
            clock = target
        }
    }
}

// MARK: 原子徽标（核 + 三条倾斜轨道 + 电子）

struct AtomView: View {
    @State private var spin = false

    private var theta: Double { (spin ? 360.0 : 0.0) * .pi / 180 }

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color(red: 0.353, green: 0.784, blue: 0.980), .blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 16, height: 16)
                .shadow(color: .blue.opacity(0.55), radius: 9)

            ForEach(0..<3, id: \.self) { i in
                let tilt = Double(i) * 60
                Ellipse()
                    .stroke(.blue.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 96, height: 34)
                    .rotationEffect(.degrees(tilt))

                Circle()
                    .fill(Color(red: 0.353, green: 0.784, blue: 0.980))
                    .frame(width: 7, height: 7)
                    .shadow(color: Color(red: 0.353, green: 0.784, blue: 0.980).opacity(0.8), radius: 4)
                    .offset(
                        x: 48 * cos(theta + Double(i) * 2.0944),
                        y: 17 * sin(theta + Double(i) * 2.0944)
                    )
                    .rotationEffect(.degrees(tilt))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.7).repeatForever(autoreverses: false)) {
                spin = true
            }
        }
    }
}
