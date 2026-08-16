import Foundation

// MARK: - 数据模型（对齐 detection-strategy.md 与 swiftui-mapping.md）

/// 检测类型；判定优先级 = rawValue 顺序以外的检测顺序见 AppScanner.detect
public enum AppType: String, CaseIterable, Sendable {
    case electron
    case cef
    case nwjs
    case tauri
    case wails
    case browser   // Tier 3：完整浏览器，仅列出供参考

    public var label: String {
        switch self {
        case .electron: "Electron"
        case .cef: "CEF"
        case .nwjs: "NW.js"
        case .tauri: "Tauri"
        case .wails: "Wails"
        case .browser: "浏览器"
        }
    }

    /// Tier 2 间接特征推断，准确率有限
    public var isExperimental: Bool { self == .tauri || self == .wails }
}

/// 版本健康状态：绿 / 绿 / 黄 / 红 / 灰 五档
public enum VersionStatus: String, CaseIterable, Sendable {
    case current
    case ok
    case aging
    case outdated
    case unknown

    public var label: String {
        switch self {
        case .current: "版本较新"
        case .ok: "版本正常"
        case .aging: "建议更新"
        case .outdated: "版本老旧"
        case .unknown: "未知版本"
        }
    }
}

public struct DetectedApp: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let path: String
    public let bundleID: String?
    public let type: AppType
    public let version: String?
    public let status: VersionStatus
    /// .app 本身占用（递归分配大小）
    public let bodyBytes: Int64
    /// ~/Library 下用户数据合计（Application Support / Caches / Containers）
    public let dataBytes: Int64

    public var totalBytes: Int64 { bodyBytes + dataBytes }

    public init(
        name: String,
        path: String,
        bundleID: String?,
        type: AppType,
        version: String?,
        status: VersionStatus,
        bodyBytes: Int64,
        dataBytes: Int64
    ) {
        self.name = name
        self.path = path
        self.bundleID = bundleID
        self.type = type
        self.version = version
        self.status = status
        self.bodyBytes = bodyBytes
        self.dataBytes = dataBytes
    }
}

// MARK: - 版本新旧判定（对照 detection-strategy.md 的 Electron / Chromium 表）

public enum VersionBands {
    static func major(_ version: String?) -> Int? {
        guard let first = version?
            .split(separator: ".")
            .first
            .flatMap({ Int($0.filter(\.isNumber)) })
        else { return nil }
        return first
    }

    /// Electron 版本带：33+ 绿 / 30-32 绿 / 28-29 绿 / 25-27 黄 / <25 红
    public static func electronStatus(_ version: String?) -> VersionStatus {
        guard let m = major(version) else { return .unknown }
        switch m {
        case 33...: return .current
        case 28...32: return .ok
        case 25...27: return .aging
        default: return .outdated
        }
    }

    /// CEF 版本与 Chromium 对齐（CEF 120 = Chromium 120）
    public static func chromiumStatus(_ version: String?) -> VersionStatus {
        guard let m = major(version) else { return .unknown }
        switch m {
        case 130...: return .current
        case 120...129: return .ok
        case 114...119: return .aging
        default: return .outdated
        }
    }
}
