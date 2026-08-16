import SwiftUI

// MARK: 概念① 标签页瀑布
// matchedGeometryEffect：标签条中的标签与网格中的图标共享同一几何 id，
// 状态翻转时 SwiftUI 自动补间位置与尺寸——「标签变形为图标」的原生表达。

struct ConceptTabsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var ns

    private enum Stage { case tab, landed }

    @State private var stages: [Stage] = Array(repeating: .tab, count: SampleData.count)
    @State private var tabsShown = 0
    @State private var stripIn = false
    @State private var rotation: [Double] = Array(repeating: 0, count: SampleData.count)
    @State private var captured = 0
    @State private var capturedMB = 0
    @State private var toast = false

    var body: some View {
        ConceptFrame(info: .tabs, captured: captured, capturedMB: capturedMB) {
            ZStack {
                grid
                strip
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 10)
                if toast {
                    ToastView(text: "你装了 35 个『浏览器』")
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .clipped()
        }
        .task { await run() }
    }

    // MARK: 网格（图标为 matched 几何的落点）

    private var grid: some View {
        IconGrid { app in
            let landed = stages[app.id] == .landed
            VStack(spacing: 4) {
                Group {
                    if landed {
                        AppIconView(app: app)
                            .matchedGeometryEffect(id: app.id, in: ns, isSource: landed)
                            .rotationEffect(.degrees(rotation[app.id]))
                    } else {
                        Color.clear.frame(width: 44, height: 44)
                    }
                }
                labels(app)
            }
            .frame(width: GridGeom.cellW, height: GridGeom.cellH)
            .opacity(landed ? 1 : 0)
            .scaleEffect(y: landed ? 1 : 0.92)
        }
        .frame(width: GridGeom.width, height: GridGeom.height)
    }

    private func labels(_ app: SampleApp) -> some View {
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

    // MARK: 标签条

    private var strip: some View {
        HStack(spacing: 2) {
            ForEach(SampleData.apps) { app in
                let isTab = stages[app.id] == .tab
                Group {
                    if isTab {
                        tabShape(app)
                            .matchedGeometryEffect(id: app.id, in: ns, isSource: isTab)
                    } else {
                        Color.clear.frame(height: 24)
                    }
                }
                .opacity(app.id < tabsShown ? 1 : 0)
                .scaleEffect(app.id < tabsShown ? 1 : 0.6)
            }
        }
        .padding(.horizontal, 5)
        .padding(.top, 5)
        .frame(width: 640, alignment: .leading)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        )
        .opacity(stripIn ? 1 : 0)
        .offset(y: stripIn ? 0 : -14)
    }

    private func tabShape(_ app: SampleApp) -> some View {
        ZStack {
            UnevenRoundedRectangle(topLeadingRadius: 7, topTrailingRadius: 7, style: .continuous)
                .fill(LinearGradient(
                    colors: [app.type.light.opacity(0.9), app.type.base.opacity(0.9)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            Text(SampleData.initials(app.name))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 2)
        }
        .frame(height: 24)
        .frame(maxWidth: .infinity)
    }

    // MARK: 时间线

    private func run() async {
        if reduceMotion {
            tabsShown = SampleData.count
            stages = Array(repeating: .landed, count: SampleData.count)
            captured = SampleData.count
            capturedMB = SampleData.sumMB
            return
        }

        // 阶段一：标签条滑入，⌘T 狂开标签（12ms 一个，逐个压缩）
        withAnimation(.easeOut(duration: 0.18)) { stripIn = true }
        do {
            for i in 0..<SampleData.count {
                try await Task.sleep(for: .milliseconds(12))
                withAnimation(.easeOut(duration: 0.11)) { tabsShown = i + 1 }
            }
            try await Task.sleep(for: .milliseconds(170))

            // 阶段二：标签依次「掉出」标签条，matched 变形飞向网格槽位
            for i in 0..<SampleData.count {
                try await Task.sleep(for: .milliseconds(20))
                flip(i)
                Task {
                    try? await Task.sleep(for: .milliseconds(390))
                    captured += 1
                    capturedMB += SampleData.apps[i].totalMB
                }
            }

            // 阶段三：收尾微文案
            try await Task.sleep(for: .milliseconds(650))
            withAnimation(.easeOut(duration: 0.2)) { toast = true }
            try await Task.sleep(for: .milliseconds(1200))
            withAnimation(.easeIn(duration: 0.25)) { toast = false }
        } catch {
            // 概念切换 / 重播导致任务取消，直接放弃剩余时间线
        }
    }

    private func flip(_ i: Int) {
        rotation[i] = Double.random(in: -13...13)
        withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
            stages[i] = .landed
        }
        withAnimation(.easeOut(duration: 0.3)) {
            rotation[i] = 0
        }
    }
}
