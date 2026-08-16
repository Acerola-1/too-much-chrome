import SwiftUI

// MARK: 概念④ 数据弹射
// 飞行距离 ∝ 存储体积：Docker Desktop 冲得最远、落得最深。
// 用 KeyframeAnimator + KeyframeTrack 表达：位移 / 缩放 / 透明度多轨并行，
// 峰值点 → 弧线中点 → 落地压缩 → 弹性回正，全部声明在一个 keyframes 闭包里。

struct ConceptLaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Ripple: Identifiable {
        let id = UUID()
        let index: Int
        let color: Color
        let scale: CGFloat
    }

    /// 多轨动画值（Animatable 通过 AnimatablePair 链展开）
    struct LaunchValue: Animatable, Equatable {
        var ox: CGFloat = 0
        var oy: CGFloat = 0
        var sx: CGFloat = 1
        var sy: CGFloat = 1
        var opacity: Double = 0

        var animatableData: AnimatablePair<
            AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>,
            Double
        > {
            get {
                AnimatablePair(
                    AnimatablePair(
                        AnimatablePair(ox, oy),
                        AnimatablePair(sx, sy)
                    ),
                    opacity
                )
            }
            set {
                ox = newValue.first.first.first
                oy = newValue.first.first.second
                sx = newValue.first.second.first
                sy = newValue.first.second.second
                opacity = newValue.second
            }
        }

        static var identity: LaunchValue {
            LaunchValue(ox: 0, oy: 0, sx: 1, sy: 1, opacity: 1)
        }
    }

    /// 单个图标的弹道参数
    struct LaunchPlan {
        let index: Int
        let center: CGSize   // 网格中心相对该槽位的偏移（发射点）
        let peak: CGSize     // 峰值点相对槽位的偏移
        let arc: CGSize      // 弧线中点相对槽位的偏移
        let heavy: Double    // 体积权重 0...1
    }

    @State private var ticks: [Int] = Array(repeating: 0, count: SampleData.count)
    @State private var landed: Set<Int> = []
    @State private var captured = 0
    @State private var capturedMB = 0
    @State private var ripples: [Ripple] = []
    @State private var legend = false
    @State private var toast = false

    private let plans: [LaunchPlan] = {
        let rMax = GridGeom.maxSlotDistance * 0.92
        return (0..<SampleData.count).map { i in
            let app = SampleData.apps[i]
            let slot = GridGeom.slotOffset(i)
            var dx = slot.width
            var dy = slot.height
            var d = hypot(dx, dy)
            if d < 10 {
                // 中心列图标方向退化，改用索引均匀取角
                let angle = Double(i) / Double(SampleData.count) * 2 * .pi
                dx = CGFloat(cos(angle))
                dy = CGFloat(sin(angle))
                d = 1
            }
            let ux = dx / d
            let uy = dy / d
            let heavy = Double(app.totalMB) / Double(SampleData.maxMB)
            let peakDistance = 26 + pow(heavy, 0.6) * Double(rMax)
            // 峰值点（网格中心坐标系）
            let px = ux * CGFloat(peakDistance)
            let py = uy * CGFloat(peakDistance)
            // 弧线中点：峰值 → 槽位 的中点，加垂直偏移制造弯曲
            let mx = px / 2 - uy * 16
            let my = py / 2 + ux * 16
            // 相对槽位：中心 / 峰值 / 弧点
            return LaunchPlan(
                index: i,
                center: CGSize(width: -slot.width, height: -slot.height),
                peak: CGSize(width: px - slot.width, height: py - slot.height),
                arc: CGSize(width: mx - slot.width, height: my - slot.height),
                heavy: heavy
            )
        }
    }()

    var body: some View {
        ConceptFrame(info: .launch, captured: captured, capturedMB: capturedMB) {
            ZStack {
                IconGrid { app in
                    let plan = plans[app.id]
                    VStack(spacing: 4) {
                        AppIconView(app: app)
                            .keyframeAnimator(
                                initialValue: LaunchValue(
                                    ox: plan.center.width,
                                    oy: plan.center.height,
                                    sx: 0.2,
                                    sy: 0.2,
                                    opacity: 0
                                ),
                                trigger: ticks[app.id]
                            ) { content, value in
                                content
                                    .offset(x: value.ox, y: value.oy)
                                    .scaleEffect(x: value.sx, y: value.sy)
                                    .opacity(value.opacity)
                            } keyframes: { _ in
                                KeyframeTrack(\.opacity) {
                                    LinearKeyframe(1.0, duration: 0.06)
                                }
                                KeyframeTrack(\.ox) {
                                    LinearKeyframe(plan.peak.width, duration: 0.24)
                                    LinearKeyframe(plan.arc.width, duration: 0.16)
                                    SpringKeyframe(0, duration: 0.14, spring: .snappy(duration: 0.15))
                                }
                                KeyframeTrack(\.oy) {
                                    LinearKeyframe(plan.peak.height, duration: 0.24)
                                    LinearKeyframe(plan.arc.height, duration: 0.16)
                                    SpringKeyframe(0, duration: 0.14, spring: .snappy(duration: 0.15))
                                }
                                KeyframeTrack(\.sx) {
                                    LinearKeyframe(CGFloat(1 + plan.heavy * 0.08), duration: 0.24)
                                    LinearKeyframe(1, duration: 0.16)
                                    LinearKeyframe(CGFloat(1 + plan.heavy * 0.12), duration: 0.1)
                                    SpringKeyframe(1, duration: 0.12, spring: .snappy(duration: 0.12))
                                }
                                KeyframeTrack(\.sy) {
                                    LinearKeyframe(CGFloat(1 + plan.heavy * 0.08), duration: 0.24)
                                    LinearKeyframe(1, duration: 0.16)
                                    LinearKeyframe(CGFloat(1 - plan.heavy * 0.16), duration: 0.1)
                                    SpringKeyframe(1, duration: 0.12, spring: .snappy(duration: 0.12))
                                }
                            }
                        cellLabels(app)
                            .opacity(landed.contains(app.id) ? 1 : 0)
                    }
                    .frame(width: GridGeom.cellW, height: GridGeom.cellH)
                }
                .frame(width: GridGeom.width, height: GridGeom.height)

                ForEach(ripples) { ripple in
                    RippleView(color: ripple.color, scale: ripple.scale)
                        .offset(GridGeom.slotOffset(ripple.index))
                }

                if legend {
                    ToastView(text: "飞得越远 = 占得越多", mini: true)
                        .offset(y: -GridGeom.height * 0.32)
                        .transition(.opacity)
                }
                if toast {
                    ToastView(text: "\(SampleData.sumGBText) GB 已各就各位")
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .clipped()
        }
        .task { await run() }
    }

    private func cellLabels(_ app: SampleApp) -> some View {
        VStack(spacing: 1) {
            Text(app.name)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 2)
            Text(app.sizeText)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 时间线（体积大的先发射）

    private func run() async {
        if reduceMotion {
            landed = Set(0..<SampleData.count)
            captured = SampleData.count
            capturedMB = SampleData.sumMB
            return
        }

        do {
            withAnimation(.easeOut(duration: 0.2)) { legend = true }

            let order = (0..<SampleData.count)
                .map { ($0, Double(SampleData.apps[$0].totalMB)) }
                .sorted { $0.1 > $1.1 }

            for (rank, entry) in order.enumerated() {
                try await Task.sleep(for: .milliseconds(rank == 0 ? 300 : 24))
                fire(entry.0)
            }

            try await Task.sleep(for: .milliseconds(1000))
            withAnimation(.easeIn(duration: 0.2)) { legend = false }
            withAnimation(.easeOut(duration: 0.2)) { toast = true }
            try await Task.sleep(for: .milliseconds(1000))
            withAnimation(.easeIn(duration: 0.25)) { toast = false }
        } catch {
            // 任务取消（切换 / 重播）
        }
    }

    private func fire(_ i: Int) {
        ticks[i] += 1
        let plan = plans[i]
        let flightMS = Int(500 + plan.heavy * 170 + 120)
        Task {
            try? await Task.sleep(for: .milliseconds(flightMS))
            let app = SampleData.apps[i]
            landed.insert(i)
            ripples.append(Ripple(
                index: i,
                color: app.type.base,
                scale: 0.6 + CGFloat(plan.heavy) * 1.6
            ))
            captured += 1
            capturedMB += app.totalMB
        }
    }
}
