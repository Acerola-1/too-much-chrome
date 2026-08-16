import SwiftUI
import AppKit
import TooMuchChromeCore

// MARK: - 主界面：悬浮玻璃工具栏 + 7 列图标网格（扫描线开场）+ 报告面板
// 原生标题栏已隐藏（.hiddenTitleBar），本视图的工具栏即窗口唯一标题区，
// 左侧留白为系统红绿灯让位——布局对齐 pages/index.html 原型。
// 工具栏为悬浮液态玻璃层，网格内容从其下方滚过——玻璃才有内容可折射/透视，
// 否则盖在不透明背景上会退化成普通材质（macOS 26 液态玻璃的正确用法）。

struct ContentView: View {
    @Environment(ScanViewModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                gridArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // 悬浮玻璃工具栏只覆盖网格区，不压住右侧报告面板
                    .overlay(alignment: .top) {
                        ToolbarView()
                    }
                if model.hasResults {
                    Divider()
                    StatsPanelView()
                        .frame(width: 340)
                        .frame(maxHeight: .infinity)
                        .transition(.opacity)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            if model.phase == .idle {
                await model.scan()
            }
        }
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
                        // 顶部为悬浮玻璃工具栏让位，滚动时图标从玻璃下方穿过
                        .padding(.top, 56)
                        // 内容不足一屏时垂直居中（原型的 align-items: center）
                        .padding(.top, verticalCenterInset(availableHeight: geo.size.height))
                    }
                }
                .opacity(model.apps.isEmpty && model.isScanning ? 0 : 1)

                if model.isScanning && !reduceMotion && model.totalCandidates > 0 {
                    ScanlineOverlay(progress: model.progress)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.phase)
    }

    /// 网格内容高度低于可视区时返回顶部留白，使网格垂直居中
    private func verticalCenterInset(availableHeight: CGFloat) -> CGFloat {
        let rows = max(1, Int(ceil(Double(model.apps.count) / 7)))
        let estimatedHeight = CGFloat(rows) * 122 + 48 + 56
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

// MARK: - 工具栏（悬浮玻璃，红绿灯让位；过滤胶囊在网格区水平居中，刷新按钮靠右）

private struct ToolbarView: View {
    @Environment(ScanViewModel.self) private var model

    var body: some View {
        ZStack {
            // 过滤胶囊在网格区水平居中
            filterCapsules

            // 刷新按钮靠右，与胶囊分层摆放避免遮挡
            HStack {
                Spacer()
                GlassGroup(spacing: 10) {
                    rescanButton
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        // 玻璃自带边缘高光与阴影，不再叠加 Divider
        .liquidGlassBar()
    }

    // MARK: 过滤胶囊（常驻全部类型——对齐原型；0 命中类型降透明度但仍可点）

    private var filterCapsules: some View {
        HStack(spacing: 3) {
            filterChip(type: nil, label: "全部")
            ForEach(AppType.allCases, id: \.self) { type in
                filterChip(type: type, label: type.label)
            }
        }
        .padding(3)
        .liquidGlass(in: Capsule(style: .continuous))
        .opacity(model.hasResults ? 1 : 0.4)
        .animation(.easeInOut(duration: 0.2), value: model.hasResults)
        .disabled(model.isScanning)
    }

    private func filterChip(type: AppType?, label: String) -> some View {
        let selected = model.filter == type
        let count: Int = {
            guard let type else { return model.apps.count }
            return model.apps.filter { $0.type == type }.count
        }()
        return Button {
            model.filter = type
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(selected ? Color.accentColor : Color.clear)
                )
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .opacity(count == 0 && !selected ? 0.45 : 1)
        .help(count == 0 ? "\(label)：未检出" : "\(label) · \(count) 个")
    }

    // MARK: 重扫按钮（交互式玻璃）

    private var rescanButton: some View {
        Button {
            Task { await model.rescan() }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
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
}

// MARK: - 扫描线（绑定真实扫描进度）

private struct ScanlineOverlay: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
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
            .offset(x: -64 + progress * (geo.size.width + 128))
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
                        StatusDot(status: app.status)
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
