import SwiftUI
import AppKit
import TooMuchChromeCore

// MARK: - 液态玻璃（macOS 26+，低版本回退毛玻璃材质）

extension View {
    /// 液态玻璃（macOS 26+），interactive 提供按压反馈；回退 .regularMaterial
    @ViewBuilder
    func liquidGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if interactive {
                glassEffect(.regular.interactive(), in: shape)
            } else {
                glassEffect(.regular, in: shape)
            }
        } else {
            background(.regularMaterial, in: shape)
        }
    }
}

// MARK: - 类型与状态配色

extension AppType {
    var color: Color {
        switch self {
        case .electron: Color(red: 0, green: 0.478, blue: 1)        // #007aff
        case .cef:      Color(red: 1, green: 0.62, blue: 0.04)      // #ff9f0a
        case .nwjs:     Color(red: 0.345, green: 0.337, blue: 0.84) // #5856d6
        case .tauri:    Color(red: 0.545, green: 0.361, blue: 0.965) // #8b5cf6
        case .wails:    Color(red: 0.024, green: 0.714, blue: 0.831) // #06b6d4
        case .browser:  Color(red: 0.596, green: 0.596, blue: 0.616) // #98989d
        }
    }
}

extension VersionStatus {
    var color: Color {
        switch self {
        case .current, .ok: Color(red: 0.204, green: 0.78, blue: 0.347)   // #34c759
        case .aging:        Color(red: 1, green: 0.62, blue: 0.04)        // #ff9f0a
        case .outdated:     Color(red: 1, green: 0.227, blue: 0.188)      // #ff3b30
        case .unknown:      Color(red: 0.682, green: 0.682, blue: 0.698)  // #aeaeb2
        }
    }
}

/// 小圆角胶囊徽章
struct Badge: View {
    let text: String
    let foreground: Color
    let background: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(background))
    }
}

/// 图标右下角的健康状态点（带底色描边）
struct StatusDot: View {
    let status: VersionStatus

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .frame(width: 15, height: 15)
            Circle()
                .fill(status.color)
                .frame(width: 11, height: 11)
        }
        .help(status.label)
    }
}

/// 本体 / 用户数据 双段条
struct SplitBar: View {
    let bodyFraction: Double
    let dataFraction: Double
    let bodyColor: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(LinearGradient(
                        colors: [bodyColor.opacity(0.75), bodyColor],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: max(0, geo.size.width * bodyFraction))
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: max(0, geo.size.width * dataFraction))
            }
            .clipShape(Capsule())
        }
        .frame(height: height)
    }
}

/// 区块小标题
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.6)
    }
}
