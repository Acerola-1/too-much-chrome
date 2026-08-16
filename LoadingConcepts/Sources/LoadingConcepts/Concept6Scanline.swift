import SwiftUI

// MARK: 概念⑥ 复印机扫描线
// 光条线性扫过网格，图标按列去模糊显现——诚实、冷静、绝对稳的兜底方案。

struct ConceptScanlineView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var revealed: Set<Int> = []
    @State private var barX: CGFloat = -70
    @State private var barOn = false
    @State private var captured = 0
    @State private var capturedMB = 0
    @State private var toast = false

    private let sweepDuration: Double = 1.1

    var body: some View {
        ConceptFrame(info: .scanline, captured: captured, capturedMB: capturedMB) {
            ZStack {
                IconGrid { app in
                    let on = revealed.contains(app.id)
                    IconCell(app: app)
                        .opacity(on ? 1 : 0)
                        .blur(radius: on ? 0 : 10)
                        .scaleEffect(on ? 1 : 0.96)
                        .animation(.easeOut(duration: 0.3), value: revealed)
                }
                .frame(width: GridGeom.width, height: GridGeom.height)

                if barOn {
                    scanlineBar
                        .offset(x: barX)
                        .transition(.opacity)
                }

                if toast {
                    ToastView(text: "扫描完毕 · 35 个应用")
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .clipped()
        }
        .task { await run() }
    }

    private var scanlineBar: some View {
        ZStack(alignment: .trailing) {
            LinearGradient(
                stops: [
                    .init(color: .blue.opacity(0), location: 0),
                    .init(color: .blue.opacity(0.05), location: 0.55),
                    .init(color: .blue.opacity(0.14), location: 0.9),
                    .init(color: Color(red: 0.47, green: 0.76, blue: 1).opacity(0.5), location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            Rectangle()
                .fill(Color(red: 0.47, green: 0.76, blue: 1).opacity(0.85))
                .frame(width: 2)
                .shadow(color: .blue.opacity(0.6), radius: 6)
        }
        .frame(width: 64)
        .frame(maxHeight: .infinity)
    }

    // MARK: 时间线（列中心 X 决定被扫中的时刻）

    private func run() async {
        if reduceMotion {
            revealed = Set(0..<SampleData.count)
            captured = SampleData.count
            capturedMB = SampleData.sumMB
            return
        }

        barOn = true
        barX = -70
        do {
            try await Task.sleep(for: .milliseconds(60))
            withAnimation(.linear(duration: sweepDuration)) {
                barX = GridGeom.width + 70
            }

            var clock = 60.0
            for col in 0..<GridGeom.cols {
                let colX = Double(col - (GridGeom.cols - 1) / 2) * Double(GridGeom.cellW + GridGeom.hGap)
                let t = 60 + sweepDuration * 1000
                    * ((Double(GridGeom.width) / 2 + colX) / Double(GridGeom.width)) * 0.96
                if t > clock {
                    try await Task.sleep(for: .milliseconds(Int(t - clock)))
                    clock = t
                }
                for row in 0..<GridGeom.rows {
                    let index = row * GridGeom.cols + col
                    withAnimation(.easeOut(duration: 0.3)) {
                        revealed.insert(index)
                    }
                    captured += 1
                    capturedMB += SampleData.apps[index].totalMB
                    try await Task.sleep(for: .milliseconds(45))
                    clock += 45
                }
            }

            try await Task.sleep(for: .milliseconds(220))
            withAnimation(.easeOut(duration: 0.24)) { barOn = false }
            try await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeOut(duration: 0.2)) { toast = true }
            try await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeIn(duration: 0.25)) { toast = false }
        } catch {
            // 任务取消（切换 / 重播）
        }
    }
}
