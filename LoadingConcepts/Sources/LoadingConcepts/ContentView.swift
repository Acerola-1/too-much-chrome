import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: LabModel
    @State private var replaySpin: Double = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                pickerRow
                conceptStage
                    .id("\(model.concept)-\(model.run)")
                descriptionCard
                footNote
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            guard model.autoCycle else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return
                }
                model.select((model.concept + 1) % ConceptInfo.all.count)
            }
        }
    }

    // MARK: 子视图

    private var header: some View {
        VStack(spacing: 6) {
            Text("加载动画 · 六概念对比台")
                .font(.system(size: 24, weight: .bold))
            Text("SwiftUI 原生实现（macOS 14+）· 数字键 1–6 切换 · R 重播 · 系统开启「减少动态效果」时自动降级为直接显现")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var pickerRow: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(ConceptInfo.all) { info in
                    conceptButton(info)
                }
            }
            .padding(4)
            .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.06)))
            Spacer()
            replayButton
        }
    }

    private func conceptButton(_ info: ConceptInfo) -> some View {
        let selected = model.concept == info.id
        return Button {
            model.select(info.id)
        } label: {
            Text(info.label)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? Color.accentColor : Color.clear)
                )
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private var replayButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.5)) { replaySpin += 360 }
            model.replay()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 34, height: 34)
                .background(Circle().fill(.regularMaterial))
                .overlay(Circle().strokeBorder(.quaternary))
                .rotationEffect(.degrees(replaySpin))
        }
        .buttonStyle(.plain)
        .help("重播当前概念（R）")
    }

    @ViewBuilder
    private var conceptStage: some View {
        switch model.concept {
        case 0: ConceptTabsView()
        case 1: ConceptRadarView()
        case 2: ConceptMitosisView()
        case 3: ConceptLaunchView()
        case 4: ConceptBoidsView()
        default: ConceptScanlineView()
        }
    }

    private var descriptionCard: some View {
        let info = ConceptInfo.all[model.concept]
        return HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text(info.tagline)
                    .font(.system(size: 15, weight: .semibold))
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(info.points.enumerated()), id: \.offset) { _, point in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 5, height: 5)
                                .padding(.top, 5)
                            Text(point)
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(Array(info.meta.enumerated()), id: \.offset) { i, m in
                    Text(m)
                        .font(.system(size: 11))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(
                                i == 0 ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06)
                            )
                        )
                        .foregroundStyle(i == 0 ? Color.accentColor : Color.secondary)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary))
    }

    private var footNote: some View {
        Text("每个概念结束后状态栏数值即最终统计 · 数据与 too-much-chrome.design/pages 同源（28 Electron / 4 Tauri / 3 Wails）· 体积字段用于概念②的涟漪编码与概念④的距离编码")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 640)
    }
}
