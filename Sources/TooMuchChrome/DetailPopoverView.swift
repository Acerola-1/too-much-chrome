import SwiftUI
import AppKit
import TooMuchChromeCore

// MARK: - 应用详情弹层

struct DetailPopoverView: View {
    @Environment(ScanViewModel.self) private var model

    let app: DetectedApp

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            storageBreakdown
            Divider()
            pathSection
            revealButton
        }
        .padding(14)
        .frame(width: 280)
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: model.icon(for: app))
                .resizable()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Badge(
                        text: app.type.label,
                        foreground: app.type.color,
                        background: app.type.color.opacity(0.14)
                    )
                    if let version = app.version, !version.isEmpty {
                        Badge(
                            text: "\(app.type.label) \(version)",
                            foreground: .secondary,
                            background: Color.primary.opacity(0.07)
                        )
                    }
                    Badge(
                        text: model.displayStatus(for: app).label,
                        foreground: app.status.color,
                        background: app.status.color.opacity(0.14)
                    )
                }
            }
        }
    }

    // MARK: 存储分解

    private var storageBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "存储分解")
            Text(fmtBytes(app.totalBytes))
                .font(.system(size: 20, weight: .bold))
                .monospacedDigit()
            let total = Double(max(1, app.totalBytes))
            SplitBar(
                bodyFraction: Double(app.bodyBytes) / total,
                dataFraction: Double(app.dataBytes) / total,
                bodyColor: app.type.color
            )
            VStack(spacing: 5) {
                breakdownRow(
                    color: app.type.color,
                    label: "应用本体",
                    value: fmtBytes(app.bodyBytes)
                )
                breakdownRow(
                    color: Color.primary.opacity(0.3),
                    label: "用户数据（Application Support / Caches / Containers）",
                    value: fmtBytes(app.dataBytes)
                )
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    private func breakdownRow(color: Color, label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(label)
            }
            Spacer()
            Text(value)
                .foregroundStyle(.primary)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }

    // MARK: 安装路径

    private var pathSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "安装路径")
            Text(app.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(3)
                .truncationMode(.middle)
        }
    }

    private var revealButton: some View {
        HStack {
            Spacer()
            Button {
                let fileURL = URL(fileURLWithPath: app.path)
                NSWorkspace.shared.selectFile(
                    fileURL.path,
                    inFileViewerRootedAtPath: fileURL.deletingLastPathComponent().path
                )
            } label: {
                Label("在 Finder 中显示", systemImage: "arrow.right.circle.fill")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)
        }
    }
}
