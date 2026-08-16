import SwiftUI
import AppKit
import TooMuchChromeCore

// MARK: - 主界面：浮动玻璃工具栏 + 7 列图标网格 + 浮动玻璃报告卡片

struct ContentView: View {
    @Environment(ScanViewModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HStack(spacing: 0) {
                gridArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if model.hasResults {
                    StatsPanelView()
                        .frame(width: 336)
                        .frame(maxHeight: .infinity)
                        .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .padding([.top, .bottom, .trailing], 10)
                        .transition(.opacity)
                }
            }
        }
        .background(
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                // 极淡的全窗口双向色晕：给玻璃一点可折射的色彩，
                // 明暗模式都只是"隐约的空气感"，不再形成左右色块
                LinearGradient(
                    stops: [
                        .init(color: Color.accentColor.opacity(0.05), location: 0),
                        .init(color: .clear, location: 0.45),
                        .init(color: Color.purple.opacity(0.045), location: 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .task {
            if model.phase == .idle {
                await model.scan()
            }
        }
        // 在线版本基准与扫描并行加载，到达后各应用状态点动态重判
        .task {
            await model.refreshBaseline()
        }
    }

    // MARK: 统一浮动玻璃工具栏（唯一标题区，红绿灯由左端留白让位）

    private var toolbar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Too Much Chrome")
                    .font(.system(size: 14, weight: .semibold))
                Text(model.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.15), value: model.apps.count)
                    .animation(.easeInOut(duration: 0.15), value: model.phase)
            }
            .padding(.leading, 62)   // 让位系统红绿灯

            Spacer(minLength: 12)

            GlassSegmentedFilter()
            rescanButton
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding([.horizontal, .bottom], 10)
        .padding(.top, 6)
    }

    // MARK: 重扫按钮（交互式玻璃，编组进工具栏玻璃）

    private var rescanButton: some View {
        Button {
            Task { await model.rescan() }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 30, height: 30)
                .rotationEffect(.degrees(model.isScanning ? 360 : 0))
                .animation(
                    model.isScanning
                        ? .linear(duration: 1.0).repeatForever(autoreverses: false)
                        : .default,
                    value: model.isScanning
                )
        }
        .buttonStyle(.plain)
        .liquidGlass(in: Circle(), interactive: true)
        .disabled(model.isScanning)
        .help(model.isScanning ? "正在扫描…" : "重新扫描（⌘R）")
    }

    // MARK: 图标网格区（固定 7 列铺满，行数少时垂直居中——对齐原型）

    private var gridArea: some View {
        ZStack {
            if model.phase == .done && model.apps.isEmpty {
                emptyState
            } else {
                GeometryReader { geo in
                    ScrollView {
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.flexible(), spacing: 12),
                                count: 7
                            ),
                            spacing: 12
                        ) {
                            ForEach(model.apps) { app in
                                AppCellView(app: app)
                            }
                        }
                .padding(24)
                .frame(maxWidth: .infinity)
                .padding(.top, verticalCenterInset(availableHeight: geo.size.height))
            }
        }
        .padding(.leading, 10)
        .overlay {
            if model.isScanning && model.apps.isEmpty {
                EarlyLoadingView()
                    .transition(.opacity)
            }
        }

                if model.isScanning && !reduceMotion {
                    ScanlineOverlay(
                        progress: model.progress,
                        indeterminate: model.totalCandidates == 0
                    )
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.phase)
    }

    /// 网格内容高度低于可视区时返回顶部留白，使网格垂直居中
    private func verticalCenterInset(availableHeight: CGFloat) -> CGFloat {
        let rows = max(1, Int(ceil(Double(model.apps.count) / 7)))
        let estimatedHeight = CGFloat(rows) * 122 + 48
        guard estimatedHeight < availableHeight else { return 0 }
        return max(0, (availableHeight - estimatedHeight) / 2)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green.opacity(0.8))
            Text("未发现基于 WebView 的应用")
                .font(.system(size: 16, weight: .semibold))
            Text("你的 Mac 很干净，没有偷偷内置 Chromium 的应用")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 液态玻璃分段过滤器（滑动玻璃滑块）
// 轨道为非玻璃"凹槽"，滑块是全场唯一玻璃元素垫在选中段标签下，
// glassEffectID 使其在段间插入/移除时液态滑动（低版本回退 matchedGeometryEffect
// 滑动的强调色胶囊）；支持点按与按住横扫连续切换。

private struct GlassSegmentedFilter: View {
    @Environment(ScanViewModel.self) private var model
    @Namespace private var ns

    private var types: [AppType?] { [nil] + AppType.allCases.map(Optional.some) }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(types.enumerated()), id: \.offset) { _, type in
                segment(type)
            }
        }
        .padding(3)
        .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.07)))
        .opacity(model.hasResults ? 1 : 0.5)
        .animation(.easeInOut(duration: 0.2), value: model.hasResults)
        // 点按与横扫统一由置顶透明层分发（Button 会吞掉底层 background 上的手势）
        .overlay { sweepGestureLayer }
        .disabled(model.isScanning)
    }

    // MARK: 分段（等宽，保证横扫命中与滑块轨迹精确对齐）

    private func segment(_ type: AppType?) -> some View {
        let selected = model.filter == type
        let label = type?.label ?? "全部"
        let count = type.flatMap { model.typeCountsAll[$0] } ?? model.apps.count
        return Button {
            select(type)
        } label: {
            Text(label)
                .font(.system(size: 12, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .lineLimit(1)
                .frame(width: 64, height: 24)
                        .background {
                            if selected { thumb }
                        }
                        .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(count == 0 && !selected ? 0.45 : 1)
        .help(count == 0 ? "\(label)：未检出" : "\(label) · \(count) 个")
    }

    /// 滑块：macOS 26 液态玻璃（glassEffectID 跨段滑动）；低版本强调色胶囊
    @ViewBuilder
    private var thumb: some View {
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(
                    .regular.tint(Color.white.opacity(0.16)),
                    in: Capsule(style: .continuous)
                )
                .glassEffectID("filter-thumb", in: ns)
        } else {
            Capsule(style: .continuous)
                .fill(Color.accentColor)
                .matchedGeometryEffect(id: "filter-thumb", in: ns)
        }
    }

    private func select(_ type: AppType?) {
        guard model.filter != type else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            model.filter = type
        }
    }

    /// 等宽分段命中：按横向坐标返回对应过滤类型
    private func filterType(atX x: CGFloat, width: CGFloat) -> AppType? {
        let count = types.count
        let segmentWidth = width / CGFloat(count)
        let index = min(count - 1, max(0, Int(x / segmentWidth)))
        return types[index]
    }

    private var sweepGestureLayer: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    // 拖动横扫：指针划到哪个标签就切到哪个（液态玻璃 tab 手感）
                    DragGesture(minimumDistance: 3)
                        .onChanged { value in
                            select(filterType(atX: value.location.x, width: geo.size.width))
                        }
                )
                .onTapGesture { location in
                    select(filterType(atX: location.x, width: geo.size.width))
                }
        }
    }
}

// MARK: - 早期加载提示（扫描中且尚无结果时居中显示，与扫描线同期出现）

private struct EarlyLoadingView: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("正在扫描已安装的应用…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

// MARK: - 扫描线（绑定真实扫描进度）

private struct ScanlineOverlay: View {
    let progress: Double
    /// 枚举阶段（候选数未知）用不确定动画循环，避免白屏等待
    var indeterminate: Bool = false

    @State private var sweep = false

    var body: some View {
        GeometryReader { geo in
            let lineX = indeterminate
                ? (sweep ? geo.size.width + 64 : -64)
                : -64 + progress * (geo.size.width + 128)
            ZStack(alignment: .trailing) {
                LinearGradient(
                    stops: [
                        .init(color: .accentColor.opacity(0), location: 0),
                        .init(color: .accentColor.opacity(0.05), location: 0.55),
                        .init(color: .accentColor.opacity(0.14), location: 0.9),
                        .init(color: Color(red: 0.47, green: 0.76, blue: 1).opacity(0.5), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                Rectangle()
                    .fill(Color(red: 0.47, green: 0.76, blue: 1).opacity(0.85))
                    .frame(width: 2)
                    .shadow(color: .accentColor.opacity(0.6), radius: 6)
            }
            .frame(width: 64)
            .offset(x: lineX)
            .onAppear {
                guard indeterminate else { return }
                withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: false)) {
                    sweep = true
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 图标单元格

private struct AppCellView: View {
    @Environment(ScanViewModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let app: DetectedApp

    @State private var appeared = false
    @State private var showPopover = false

    private var dimmed: Bool {
        model.filter != nil && app.type != model.filter
    }

    var body: some View {
        Button {
            model.setLinked(app.id)
            showPopover = true
        } label: {
            VStack(spacing: 6) {
                Image(nsImage: model.icon(for: app))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        StatusDot(status: model.displayStatus(for: app))
                            .offset(x: 3, y: 3)
                    }
                Text(app.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity)
                Text(fmtBytes(app.totalBytes))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(model.linkedID == app.id ? Color.accentColor.opacity(0.12) : .clear)
            )
            .opacity(dimmed ? 0.14 : (appeared || reduceMotion ? 1 : 0))
            .blur(radius: appeared || reduceMotion ? 0 : 10)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!dimmed)
        .help("\(app.name) · \(app.type.label) · \(fmtBytes(app.totalBytes))")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.3)) { appeared = true }
        }
        .popover(isPresented: $showPopover) {
            DetailPopoverView(app: app)
        }
    }
}
