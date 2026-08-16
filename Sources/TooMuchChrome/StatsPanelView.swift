import SwiftUI
import AppKit
import TooMuchChromeCore

// MARK: - 右侧报告面板：总数 / 存储占用 / 类型分布 / 排行 / 健康度

struct StatsPanelView: View {
    @Environment(ScanViewModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                totalSection
                Divider()
                storageSection
                if model.filter == nil, !model.typeCounts.isEmpty {
                    Divider()
                    donutSection
                }
                Divider()
                rankingSection
                Divider()
                healthSection
            }
            .padding(20)
        }
        // 玻璃面板叠在带微弱色彩渐变的底上，透出玻璃质感（纯色底会退化成普通材质）
        .liquidGlassBar()
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.06),
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    // MARK: 总应用数

    private var totalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "总应用数")
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(model.filteredApps.count)")
                    .font(.system(size: 44, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: model.filteredApps.count)
                Text("个")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            Text("基于 WebView / Chromium 的 macOS 应用")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 存储占用

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "存储占用")
            HStack {
                Text("合计")
                    .font(.system(size: 13))
                Spacer()
                Text(fmtBytes(model.totalBytes))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: model.totalBytes)
            }
            let total = Double(max(1, model.totalBytes))
            SplitBar(
                bodyFraction: Double(model.bodyBytes) / total,
                dataFraction: Double(model.dataBytes) / total,
                bodyColor: .accentColor
            )
            HStack(spacing: 14) {
                legendDot(color: .accentColor, label: "应用本体", value: fmtBytes(model.bodyBytes))
                legendDot(color: Color.primary.opacity(0.3), label: "用户数据", value: fmtBytes(model.dataBytes))
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    private func legendDot(color: Color, label: String, value: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(label) \(value)")
        }
    }

    // MARK: 类型分布（环形）

    private var donutSection: some View {
        let items = model.typeCounts
        let total = max(1, items.reduce(0) { $0 + $1.count })

        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "类型分布")
            HStack(spacing: 18) {
                ZStack {
                    ForEach(donutSegments(items, total: total)) { seg in
                        Circle()
                            .trim(from: seg.start, to: seg.end)
                            .stroke(seg.color, lineWidth: 13)
                            .rotationEffect(.degrees(-90))
                    }
                    VStack(spacing: 2) {
                        Text("\(items.reduce(0) { $0 + $1.count })")
                            .font(.system(size: 24, weight: .bold))
                            .monospacedDigit()
                        Text("应用")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 104, height: 104)
                .animation(.easeInOut(duration: 0.5), value: model.apps.count)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items) { item in
                        HStack {
                            HStack(spacing: 6) {
                                Circle().fill(item.type.color).frame(width: 7, height: 7)
                                Text(item.type.label)
                                    .font(.system(size: 12, weight: .medium))
                                if item.type.isExperimental {
                                    Text("?")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .help("实验性检测，准确率有限")
                                }
                            }
                            Spacer()
                            Text("\(item.count) · \(Double(item.count) / Double(total) * 100, format: .number.precision(.fractionLength(1)))%")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    private struct DonutSegment: Identifiable {
        let id: String
        let start: CGFloat
        let end: CGFloat
        let color: Color
    }

    /// 环形分段（留 0.6% 间隙，对齐原型的分段留白）
    private func donutSegments(_ items: [ScanViewModel.TypeCount], total: Int) -> [DonutSegment] {
        let gap: CGFloat = 0.006
        var acc: CGFloat = 0
        var segs: [DonutSegment] = []
        for item in items {
            let fraction = CGFloat(item.count) / CGFloat(max(1, total))
            if fraction > 0 {
                segs.append(DonutSegment(
                    id: item.type.rawValue,
                    start: acc + gap,
                    end: acc + fraction - gap,
                    color: item.type.color
                ))
            }
            acc += fraction
        }
        return segs
    }

    // MARK: 存储排行 Top 5

    private var rankingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "存储排行 Top 5")
            VStack(spacing: 4) {
                ForEach(model.top5) { app in
                    RankRowView(app: app)
                }
            }
        }
    }

    // MARK: 版本健康度

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "版本健康度")
            VStack(spacing: 6) {
                ForEach(model.healthCounts, id: \.status) { entry in
                    HStack {
                        HStack(spacing: 6) {
                            Circle().fill(entry.status.color).frame(width: 7, height: 7)
                            Text(entry.status.label)
                                .font(.system(size: 12))
                        }
                        Spacer()
                        Text("\(entry.count)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }
}

// MARK: - 排行行（点击联动网格图标并弹详情）

private struct RankRowView: View {
    @Environment(ScanViewModel.self) private var model

    let app: DetectedApp
    @State private var showPopover = false

    var body: some View {
        Button {
            model.setLinked(app.id)
            showPopover = true
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: model.icon(for: app))
                    .resizable()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(app.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        Text(fmtBytes(app.totalBytes))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    let maxBytes = Double(max(1, model.top5.first?.totalBytes ?? 1))
                    SplitBar(
                        bodyFraction: Double(app.bodyBytes) / maxBytes,
                        dataFraction: Double(app.dataBytes) / maxBytes,
                        bodyColor: app.type.color,
                        height: 5
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(model.linkedID == app.id ? Color.accentColor.opacity(0.12) : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover) {
            DetailPopoverView(app: app)
        }
    }
}
