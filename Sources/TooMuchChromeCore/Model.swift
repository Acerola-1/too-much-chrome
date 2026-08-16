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

// MARK: - 版本新旧判定
// 分档锚点来自 VersionCatalog（在线基准 → 24h 缓存 → 下方内置常数），
// Electron/CEF 按大版本带宽，Tauri/Wails 按主/次版本距离。

public enum VersionBands {
    public static let builtInElectronMajor = 43
    public static let builtInChromiumMajor = 151

    static func major(_ version: String?) -> Int? {
        guard let first = version?
            .split(separator: ".")
            .first
            .flatMap({ Int($0.filter(\.isNumber)) })
        else { return nil }
        return first
    }

    static func minor(_ version: String?) -> Int? {
        guard let parts = version?.split(separator: "."), parts.count > 1 else { return nil }
        return Int(parts[1].filter(\.isNumber))
    }

    /// 框架 plist 里可能是厂商塞入的应用版本（如 "3.1.10"），
    /// 早于引擎存在年代的大版本视为不可判定，避免误报"老旧"
    private static func plausibleEngineMajor(_ major: Int) -> Bool {
        major >= 20
    }

    /// 按应用类型分档（GUI 与 tmc-scan 共用；latest 为在线基准，nil 时用内置锚）
public static func status(for type: AppType, version: String?, latest: VersionBaseline?) -> VersionStatus {
    switch type {
    case .electron:
        return electronStatus(version, latestMajor: latest?.electronMajor)
    case .cef, .browser:
        return chromiumStatus(version, latestMajor: latest?.chromiumMajor)
    case .tauri:
        return tauriStatus(version, latest: latest?.tauriVersion)
    case .wails:
        return wailsStatus(version, latest: latest?.wailsVersion)
    case .nwjs:
        return .unknown
    }
}

/// Electron：锚-2 内当前（官方支持窗口）· 锚-7 内正常 · 锚-12 内建议更新 · 更早老旧
    public static func electronStatus(_ version: String?, latestMajor: Int? = nil) -> VersionStatus {
        guard let m = major(version), plausibleEngineMajor(m) else { return .unknown }
        let latest = latestMajor ?? builtInElectronMajor
        switch m {
        case (latest - 2)...: return .current
        case (latest - 7)...: return .ok
        case (latest - 12)...: return .aging
        default: return .outdated
        }
    }

    /// CEF 版本与 Chromium 对齐：锚-3 / 锚-12 / 锚-23（Chromium 四周一版）
    public static func chromiumStatus(_ version: String?, latestMajor: Int? = nil) -> VersionStatus {
        guard let m = major(version), plausibleEngineMajor(m) else { return .unknown }
        let latest = latestMajor ?? builtInChromiumMajor
        switch m {
        case (latest - 3)...: return .current
        case (latest - 12)...: return .ok
        case (latest - 23)...: return .aging
        default: return .outdated
        }
    }

    /// Tauri 运行时版本分档（latest 来自 crates.io；无基准则不判定）
    public static func tauriStatus(_ version: String?, latest: String?) -> VersionStatus {
        runtimeStatus(version, latest: latest)
    }

    /// Wails 运行时版本分档（latest 来自 Go module proxy）
    public static func wailsStatus(_ version: String?, latest: String?) -> VersionStatus {
        runtimeStatus(version, latest: latest)
    }

    /// 运行时分档：主版本相等时，次版本距锚 ≤2 当前、≤6 正常、更远偏旧；
    /// 主版本落后 1 代偏旧、≥2 代老旧（Tauri/Wails 主版本仅 1/2 量级，
    /// 不适用 plausibleEngineMajor 的 ≥20 防线）
    static func runtimeStatus(_ version: String?, latest: String?) -> VersionStatus {
        guard let version, let latest,
              let vMaj = major(version), let lMaj = major(latest),
              vMaj > 0, lMaj > 0
        else { return .unknown }
        let vMin = minor(version) ?? 0
        let lMin = minor(latest) ?? 0
        if vMaj == lMaj {
            if vMin >= lMin - 2 { return .current }
            if vMin >= lMin - 6 { return .ok }
            return .aging
        }
        return vMaj <= lMaj - 2 ? .outdated : .aging
    }
}
