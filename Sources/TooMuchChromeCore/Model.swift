import Foundation

// MARK: - 数据模型（对齐 detection-strategy.md 与 swiftui-mapping.md）

/// 检测类型；判定优先级 = 检测顺序，见 AppScanner.detect。
/// allCases 顺序即 UI 分段条的排列顺序：自带内核 → 系统内核 → 浏览器 → 系统 WebView
public enum AppType: String, CaseIterable, Sendable {
    case electron
    case cef
    case nwjs
    /// 厂商自研的 Chromium 派生内核：框架名、Bundle ID 均为厂商自有，且既无 Electron
    /// 也无 CEF 的家族标记（实测微信 XWeb、内核 Chromium 144）
    case vendorChromium
    case tauri
    case wails
    case flutter       // Tier 2：Flutter 应用 + WebView 插件
    case browser       // Tier 3：完整浏览器，仅列出供参考
    case systemWebView // Tier 4：WKWebView 承载 + 独立前端资源

    public var label: String {
        switch self {
        case .electron: "Electron"
        case .cef: "CEF"
        case .nwjs: "NW.js"
        case .vendorChromium: "自研内核"
        case .tauri: "Tauri"
        case .wails: "Wails"
        case .flutter: "Flutter"
        case .browser: "浏览器"
        case .systemWebView: "WebView"
        }
    }

    /// 完整名称：分段条按等宽排布，label 需短；悬停提示用这个展开说明
    public var fullLabel: String {
        switch self {
        case .vendorChromium: "自研 Chromium 派生内核"
        case .systemWebView: "系统 WebView（WKWebView 承载）"
        case .flutter: "Flutter WebView"
        default: label
        }
    }

    /// 间接特征推断，准确率有限。自研内核不算：它"在分发 Chromium"这件事是二进制实锤，
    /// 只是家族名字不可知
    public var isExperimental: Bool {
        switch self {
        case .tauri, .wails, .flutter, .systemWebView: true
        case .electron, .cef, .nwjs, .vendorChromium, .browser: false
        }
    }
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
    public static let builtInElectronMajor = 44
    public static let builtInChromiumMajor = 152

    /// Electron 大版本合理区间上限 = 锚点 + 该余量。
    /// 超过即说明框架 plist 里写的不是 Electron 版本，而是 Chromium 方案
    /// （实测 ChatGPT 的框架被改名成 Codex Framework 后版本写为 "152.0.7977.83"）
    static let electronMajorHeadroom = 20

    /// CEF/Chromium 大版本可信下限：低于此值视为厂商塞入的应用版本
    /// （实测网易云 CEF 框架 plist 写的是应用版本 "3.1.11"，真实内核为 116）
    static let chromiumMajorFloor = 20

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

    /// 按应用类型分档（GUI 与 tmc-scan 共用；latest 为在线基准，nil 时用内置锚）
public static func status(for type: AppType, version: String?, latest: VersionBaseline?) -> VersionStatus {
    switch type {
    case .electron:
        return electronStatus(version, latestMajor: latest?.electronMajor)
    case .cef, .browser, .vendorChromium:
        return chromiumStatus(version, latestMajor: latest?.chromiumMajor)
    case .tauri:
        return tauriStatus(version, latest: latest?.tauriVersion)
    case .wails:
        return wailsStatus(version, latest: latest?.wailsVersion)
    case .nwjs, .flutter, .systemWebView:
        return .unknown
    }
}

/// Electron：锚-2 内当前（官方支持窗口）· 锚-7 内正常 · 锚-12 内建议更新 · 更早老旧。
/// 大版本 1 起即为合法 Electron 版本（Electron 11 = Chromium 87 这类老版本真实存在，
/// 实测 aTrust 的框架 plist 就是 "11.5.0"）；只有超出锚点合理区间才改按 Chromium 分档
    public static func electronStatus(_ version: String?, latestMajor: Int? = nil) -> VersionStatus {
        guard let m = major(version), m >= 1 else { return .unknown }
        let latest = latestMajor ?? builtInElectronMajor
        guard m <= latest + electronMajorHeadroom else { return chromiumStatus(version) }
        switch m {
        case (latest - 2)...: return .current
        case (latest - 7)...: return .ok
        case (latest - 12)...: return .aging
        default: return .outdated
        }
    }

    /// CEF 版本与 Chromium 对齐：锚-3 / 锚-12 / 锚-23（Chromium 四周一版）
    public static func chromiumStatus(_ version: String?, latestMajor: Int? = nil) -> VersionStatus {
        guard let m = major(version), m >= chromiumMajorFloor else { return .unknown }
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
    /// 不适用 Chromium 系的大版本阈值）
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
