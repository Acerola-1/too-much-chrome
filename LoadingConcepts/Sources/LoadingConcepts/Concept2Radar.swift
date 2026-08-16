import SwiftUI

// MARK: 概念② 雷达扫描
// AngularGradient 锥形光束做一次 414°（1.15 圈）线性旋转；
// 每个槽位按其相对扫描起点的角度计算精确的被扫中时刻，原地 ping 出图标。
// 涟漪半径与应用体积成正比——检测回波的轻重即存储的大小。

struct ConceptRadarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Ripple: Identifiable {
        let id = UUID()
        let index: Int
        let color: Color
        let scale: CGFloat
    }

    @State private var revealed: Set<Int> = []
    @State private var beamOn = false
    @State private var beamAngle: Angle = .degrees(-90)
    @State private var vignette = false
    @State private var captured = 0
    @State private var capturedMB = 0
    @State private var ripples: [Ripple] = []
    @State private var toast = false

    private let sweepDegrees: Double = 414
    private let sweepDuration: Double = 1.5
    private var beamDiameter: CGFloat { max(GridGeom.width, GridGeom.height) * 1.5 }

    var body: some View {
        ConceptFrame(info: .radar, captured: captured, capturedMB: capturedMB) {
            ZStack {
                IconGrid { app in
                    let on = revealed.contains(app.id)
                    IconCell(app: app)
                        .scaleEffect(on ? 1 : 0.25)
                        .opacity(on ? 1 : 0)
                        .animation(.spring(response: 0.26, dampingFraction: 0.55), value: revealed)
                }
                .frame(width: GridGeom.width, height: GridGeom.height)

                // 雷达装饰环
                ForEach([0.42, 0.68, 0.94], id: \.self) { k in
                    Circle()
                        .stroke(Color.blue.opacity(0.14), lineWidth: 1)
                        .frame(width: beamDiameter * k, height: beamDiameter * k)
                }

                // 扫描光束（彗尾锥形渐变）
                if beamOn {
                    beam
                        .rotationEffect(beamAngle)
                        .transition(.opacity)
                }

                // 回波涟漪
                ForEach(ripples) { ripple in
                    RippleView(color: ripple.color, scale: ripple.scale)
                        .offset(GridGeom.slotOffset(ripple.index))
                }

                if vignette {
                    Rectangle()
                        .fill(Color.black.opacity(0.22))
                        .transition(.opacity)
                }

                if toast {
                    ToastView(text: "已定位 35 个 WebView 应用")
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .clipped()
        }
        .task { await run() }
    }

    private var beam: some View {
        Circle()
            .fill(
                AngularGradient(
                    stops: [
                        .init(color: .blue.opacity(0), location: 0.0),
                        .init(color: .blue.opacity(0.02), location: 0.80),
                        .init(color: .blue.opacity(0.16), location: 0.92),
                        .init(color: .blue.opacity(0.38), location: 0.99),
                        .init(color: Color(red: 0.47, green: 0.76, blue: 1).opacity(0.6), location: 1.0)
                    ],
                    center: .center,
                    startAngle: .degrees(0),
                    endAngle: .degrees(360)
                )
            )
            .frame(width: beamDiameter, height: beamDiameter)
    }

    // MARK: 时间线

    private func run() async {
        if reduceMotion {
            revealed = Set(0..<SampleData.count)
            captured = SampleData.count
            capturedMB = SampleData.sumMB
            return
        }

        withAnimation(.easeOut(duration: 0.16)) { vignette = true }
        do {
            try await Task.sleep(for: .milliseconds(260))
            withAnimation(.easeIn(duration: 0.2)) { beamOn = true }
            try await Task.sleep(for: .milliseconds(40))

            // 光束匀速旋转 414°；揭示时刻与角度严格换算对齐
            withAnimation(.linear(duration: sweepDuration)) {
                beamAngle = .degrees(-90 + sweepDegrees)
            }

            let sorted = (0..<SampleData.count)
                .map { ($0, GridGeom.radarRelAngle($0)) }
                .sorted { $0.1 < $1.1 }

            var clock = 0.0
            for (index, angle) in sorted {
                let t = angle / sweepDegrees * sweepDuration * 1000
                if t > clock {
                    try await Task.sleep(for: .milliseconds(Int(t - clock)))
                    clock = t
                }
                let app = SampleData.apps[index]
                withAnimation(.spring(response: 0.26, dampingFraction: 0.55)) {
                    revealed.insert(index)
                }
                let heavy = Double(app.totalMB) / Double(SampleData.maxMB)
                ripples.append(Ripple(
                    index: index,
                    color: app.type.base,
                    scale: 0.7 + heavy * 2.1
                ))
                captured += 1
                capturedMB += app.totalMB
            }

            try await Task.sleep(for: .milliseconds(180))
            withAnimation(.easeOut(duration: 0.26)) { beamOn = false }
            withAnimation(.easeOut(duration: 0.3)) { vignette = false }
            try await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeOut(duration: 0.2)) { toast = true }
            try await Task.sleep(for: .milliseconds(1100))
            withAnimation(.easeIn(duration: 0.25)) { toast = false }
        } catch {
            // 任务取消（切换 / 重播）
        }
    }
}
