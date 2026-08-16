import Foundation

// MARK: - 在线版本基准
// 官方公开源（无需鉴权）：
//   Electron → npm registry · Chromium → Google VersionHistory API
//   Tauri → crates.io（要求 User-Agent）· Wails → Go module proxy
// 缓存 24h；单项失败沿用缓存值，全部失败退内置常数（VersionBands.builtIn*）。

public struct VersionBaseline: Codable, Equatable {
    public var electronMajor: Int?
    public var chromiumMajor: Int?
    public var tauriVersion: String?
    public var wailsVersion: String?
    public var fetchedAt: Date?
    public var isOnline: Bool

    public init(
        electronMajor: Int? = nil,
        chromiumMajor: Int? = nil,
        tauriVersion: String? = nil,
        wailsVersion: String? = nil,
        fetchedAt: Date? = nil,
        isOnline: Bool = false
    ) {
        self.electronMajor = electronMajor
        self.chromiumMajor = chromiumMajor
        self.tauriVersion = tauriVersion
        self.wailsVersion = wailsVersion
        self.fetchedAt = fetchedAt
        self.isOnline = isOnline
    }

    /// 面向 UI 的来源描述
    public var sourceText: String {
        if isOnline, let date = fetchedAt {
            let fmt = DateFormatter()
            fmt.dateFormat = "MM-dd HH:mm"
            return "在线 \(fmt.string(from: date))"
        }
        if fetchedAt != nil { return "缓存" }
        return "内置 2026-08"
    }

    public var summaryText: String {
        [
            electronMajor.map { "Electron \($0)" },
            chromiumMajor.map { "Chromium \($0)" },
            tauriVersion.map { "Tauri \($0)" },
            wailsVersion.map { "Wails \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

public enum VersionCatalog {

    static let cacheTTL: TimeInterval = 24 * 3600
    static let userAgent = "too-much-chrome/0.1 (github.com/acerola)"

    static var cacheURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("com.acerola.too-much-chrome/baseline.json")
    }

    /// 内置兜底基准（2026-08 校准；仅在从未联网成功时出现）
    public static let builtIn = VersionBaseline(
        electronMajor: 43,
        chromiumMajor: 151,
        isOnline: false
    )

    /// 主入口：缓存新鲜直接用；否则并发拉四个源，单项失败沿用缓存，全部失败退内置
    public static func refresh() async -> VersionBaseline {
        if let cached = loadCache(),
           let fetched = cached.fetchedAt,
           Date().timeIntervalSince(fetched) < cacheTTL {
            return cached
        }

        var result = await fetchOnline()
        let cached = loadCache()
        result.isOnline = result.electronMajor != nil || result.chromiumMajor != nil
            || result.tauriVersion != nil || result.wailsVersion != nil
        if result.isOnline {
            result.fetchedAt = Date()
            // 单项失败沿用缓存值（保持基准完整）
            if result.electronMajor == nil { result.electronMajor = cached?.electronMajor }
            if result.chromiumMajor == nil { result.chromiumMajor = cached?.chromiumMajor }
            if result.tauriVersion == nil { result.tauriVersion = cached?.tauriVersion }
            if result.wailsVersion == nil { result.wailsVersion = cached?.wailsVersion }
            saveCache(result)
            return result
        }
        // 全部失败：有缓存用过期缓存，否则内置
        if let cached, cached.fetchedAt != nil { return cached }
        return builtIn
    }

    // MARK: 在线拉取

    static func fetchOnline() async -> VersionBaseline {
        async let electron = fetchElectronMajor()
        async let chromium = fetchChromiumMajor()
        async let tauri = fetchTauriVersion()
        async let wails = fetchWailsVersion()
        return await VersionBaseline(
            electronMajor: electron,
            chromiumMajor: chromium,
            tauriVersion: tauri,
            wailsVersion: wails,
            isOnline: true
        )
    }

    static func fetchJSON(_ urlString: String, timeout: TimeInterval = 8) async -> [String: Any]? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    static func fetchElectronMajor() async -> Int? {
        guard let json = await fetchJSON("https://registry.npmjs.org/electron/latest"),
              let version = json["version"] as? String else { return nil }
        return VersionBands.major(version)
    }

    static func fetchChromiumMajor() async -> Int? {
        guard let json = await fetchJSON(
            "https://versionhistory.googleapis.com/v1/chrome/platforms/mac/channels/stable/versions?pageSize=1"
        ), let versions = json["versions"] as? [[String: Any]],
           let first = versions.first,
           let version = first["version"] as? String else { return nil }
        return VersionBands.major(version)
    }

    static func fetchTauriVersion() async -> String? {
        guard let json = await fetchJSON("https://crates.io/api/v1/crates/tauri"),
              let crate = json["crate"] as? [String: Any],
              let version = crate["max_stable_version"] as? String else { return nil }
        return version
    }

    static func fetchWailsVersion() async -> String? {
        guard let json = await fetchJSON(
            "https://proxy.golang.org/github.com/wailsapp/wails/v2/@latest"
        ), let version = json["Version"] as? String else { return nil }
        return version.hasPrefix("v") ? String(version.dropFirst()) : version
    }

    // MARK: 缓存

    static func loadCache() -> VersionBaseline? {
        guard let data = try? Data(contentsOf: cacheURL),
              let baseline = try? JSONDecoder().decode(VersionBaseline.self, from: data)
        else { return nil }
        return baseline
    }

    static func saveCache(_ baseline: VersionBaseline) {
        let dir = cacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(baseline) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }
}
