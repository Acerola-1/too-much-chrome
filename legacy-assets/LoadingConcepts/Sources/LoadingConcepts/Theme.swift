import SwiftUI

// MARK: - 共享视觉组件

struct AppIconView: View {
    let app: SampleApp
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(LinearGradient(
                    colors: [app.type.light, app.type.base],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            Text(SampleData.initials(app.name))
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
    }
}

struct IconCell: View {
    let app: SampleApp

    var body: some View {
        VStack(spacing: 4) {
            AppIconView(app: app)
            Text(app.name)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 2)
            Text(app.sizeText)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(width: GridGeom.cellW, height: GridGeom.cellH)
    }
}

/// 7×5 图标网格；每个单元格的视觉修饰由各概念自行附加
struct IconGrid<Cell: View>: View {
    @ViewBuilder var cell: (SampleApp) -> Cell

    var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.fixed(GridGeom.cellW), spacing: GridGeom.hGap),
                count: GridGeom.cols
            ),
            spacing: GridGeom.vGap
        ) {
            ForEach(SampleData.apps) { app in
                cell(app)
            }
        }
    }
}

/// 落点 / ping 涟漪
struct RippleView: View {
    let color: Color
    let scale: CGFloat

    @State private var grown = false

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 2)
            .frame(width: 22, height: 22)
            .scaleEffect(grown ? scale : 0.25)
            .opacity(grown ? 0 : 0.7)
            .onAppear {
                withAnimation(.easeOut(duration: 0.48)) { grown = true }
            }
    }
}

/// 微文案 toast
struct ToastView: View {
    let text: String
    var mini = false

    var body: some View {
        Text(text)
            .font(.system(size: mini ? 12 : 13, weight: mini ? .medium : .semibold))
            .foregroundStyle(mini ? Color.secondary : Color.primary)
            .padding(.horizontal, mini ? 14 : 20)
            .padding(.vertical, mini ? 7 : 10)
            .background(
                Capsule(style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
            )
            .overlay(Capsule(style: .continuous).strokeBorder(.quaternary))
    }
}

// MARK: - 概念演示窗（工具栏 / 舞台 / 状态栏）

struct ConceptFrame<Stage: View>: View {
    let info: ConceptInfo
    let captured: Int
    let capturedMB: Int

    @ViewBuilder var stage: Stage

    var body: some View {
        VStack(spacing: 0) {
            header
            stage
                .frame(maxWidth: .infinity)
                .frame(height: GridGeom.height + 32)
            statusBar
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 30, y: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.quaternary)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 14) {
            // macOS 红绿灯由窗口标题栏原生提供，此处不再自绘
            VStack(alignment: .leading, spacing: 2) {
                Text("Too Much Chrome")
                    .font(.system(size: 15, weight: .semibold))
                Text(info.label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 54)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var statusBar: some View {
        HStack {
            statusText(
                prefix: "已捕获 ",
                value: "\(captured)",
                suffix: " / \(SampleData.count) 个应用",
                tick: captured
            )
            Spacer()
            statusText(
                prefix: "合计 ",
                value: String(format: "%.1f", Double(capturedMB) / 1024),
                suffix: " GB",
                tick: capturedMB
            )
        }
        .font(.system(size: 12))
        .monospacedDigit()
        .padding(.horizontal, 20)
        .frame(height: 38)
        .overlay(alignment: .top) { Divider() }
    }

    private func statusText(prefix: String, value: String, suffix: String, tick: Int) -> some View {
        Group {
            Text(prefix).foregroundStyle(.secondary)
                + Text(value).foregroundStyle(.primary).fontWeight(.semibold)
                + Text(suffix).foregroundStyle(.secondary)
        }
        .contentTransition(.numericText())
        .animation(.easeInOut(duration: 0.2), value: tick)
    }
}
