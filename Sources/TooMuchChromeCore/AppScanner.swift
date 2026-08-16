import Foundation

// MARK: - 扫描器
// 按 detection-strategy.md 实现：
//   Tier 1  Electron / CEF / NW.js —— 框架目录特征，准确率接近 100%
//   Tier 3  完整浏览器 —— 名称 / Bundle ID 匹配，仅列出
//   Tier 2  Tauri / Wails —— Bundle ID 与资源目录关键词，实验性
//   Tier 4  未知 WebView —— 默认关闭（误报风险高）
// 扫描路径：/Applications 与 ~/Applications（顶层 .app）

public enum AppScanner {

    // MARK: 枚举候选

    public static func candidateURLs() -> [URL] {
        let fm = FileManager.default
        let dirs = [
            URL(fileURLWithPath: "/Applications"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
        var seen = Set<URL>()
        var urls: [URL] = []
        for dir in dirs {
            guard let en = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in en {
                guard url.pathExtension == "app" else { continue }
                let std = url.standardizedFileURL
                guard seen.insert(std).inserted else { continue }
                urls.append(url)
            }
        }
        return urls.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    // MARK: 单应用检测

    public static func detect(at url: URL) -> DetectedApp? {
        let fm = FileManager.default
        let contentsURL = url.appendingPathComponent("Contents")
        let frameworksURL = contentsURL.appendingPathComponent("Frameworks")
        let frameworkNames = (try? fm.contentsOfDirectory(atPath: frameworksURL.path)) ?? []
        let lowered = frameworkNames.map { $0.lowercased() }

        let plist = Bundle(url: url)?.infoDictionary ?? [:]
        let name = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let bundleID = plist["CFBundleIdentifier"] as? String
        let appVersion = (plist["CFBundleShortVersionString"] as? String)
            ?? (plist["CFBundleVersion"] as? String)

        func frameworkVersion(_ index: Int) -> String? {
            guard let bundle = Bundle(path: frameworksURL.appendingPathComponent(frameworkNames[index]).path),
                  let info = bundle.infoDictionary else { return nil }
            let short = info["CFBundleShortVersionString"] as? String
            let build = info["CFBundleVersion"] as? String
            return [short, build].compactMap { $0 }.first { !$0.isEmpty }
        }

        func build(_ type: AppType, version: String?, status: VersionStatus) -> DetectedApp {
            // 体积统计只对命中应用执行，避免给无关应用做昂贵递归；
            // 符号链接应用（如 aTrust → /Library/sangfor/SDP/aTrust.app）
            // 需解析到真实路径，否则 enumerator 不会下钻，本体体积为 0
            let sizeTarget = url.resolvingSymlinksInPath()
            let body = directorySize(sizeTarget)
            let data = userDataBytes(bundleID: bundleID, name: name)
            return DetectedApp(
                name: name,
                path: url.path,
                bundleID: bundleID,
                type: type,
                version: version,
                status: status,
                bodyBytes: body,
                dataBytes: data
            )
        }

        // Tier 1：自带 Chromium 内核的框架
        if let i = lowered.firstIndex(where: { $0.contains("electron framework") }) {
            let v = frameworkVersion(i)
            return build(.electron, version: v, status: VersionBands.electronStatus(v))
        }
        if let i = lowered.firstIndex(where: { $0.contains("chromium embedded") }) {
            let v = frameworkVersion(i)   // CEF 版本 ≈ Chromium 版本
            return build(.cef, version: v, status: VersionBands.chromiumStatus(v))
        }
        if lowered.contains(where: { $0.contains("nwjs") }) {
            return build(.nwjs, version: appVersion, status: .unknown)
        }

        // Tier 3：完整浏览器（用户本来就知道，仅列出）
        if isBrowser(name: name, bundleID: bundleID) {
            return build(.browser, version: appVersion, status: .unknown)
        }

        // Tier 2：系统 WebView 框架（实验性）
        // 三级特征：Bundle ID / 资源目录关键词 → 主二进制内的构建路径特征
        // （Rust/Tauri 与 Go/Wails 二进制会携带 .../tauri-2.x.x/src、src-tauri 等 cargo 路径，
        //   这是关键词全漏时最后的兜底，见 detection-strategy.md Tier 2 第 3 步）
        var tauriHit = matchesKeyword("tauri", name: name, bundleID: bundleID, contentsURL: contentsURL)
        var wailsHit = matchesKeyword("wails", name: name, bundleID: bundleID, contentsURL: contentsURL)
        if !tauriHit || !wailsHit {
            let score = binaryKeywordScore(at: url)
            if let score {
                tauriHit = tauriHit || score.tauri >= 5
                wailsHit = wailsHit || score.wails >= 5
            }
        }
        if tauriHit {
            return build(.tauri, version: appVersion, status: .unknown)
        }
        if wailsHit {
            return build(.wails, version: appVersion, status: .unknown)
        }

        return nil
    }

    // MARK: 匹配辅助

    private static let browserNames: Set<String> = [
        "google chrome", "microsoft edge", "chromium", "brave browser",
        "arc", "vivaldi", "opera", "opera gx"
    ]

    private static let browserBundleIDs: Set<String> = [
        "com.google.chrome", "com.microsoft.edgemac", "org.chromium.chromium",
        "com.brave.browser", "company.thebrowser.browser", "com.vivaldi.vivaldi",
        "com.operasoftware.opera", "com.operasoftware.operagx"
    ]

    private static func isBrowser(name: String, bundleID: String?) -> Bool {
        let lowered = name.lowercased()
        if browserNames.contains(lowered) { return true }
        if let bid = bundleID?.lowercased(), browserBundleIDs.contains(bid) { return true }
        return false
    }

    /// Tier 2 关键词：Bundle ID 含关键词，或 Contents/Resources 顶层条目名含关键词
    /// （覆盖 tauri.conf.json / .tauri 等；不做二进制字符串扫描，性能优先）
    private static func matchesKeyword(
        _ keyword: String, name: String, bundleID: String?, contentsURL: URL
    ) -> Bool {
        if let bid = bundleID?.lowercased(), bid.contains(keyword) { return true }
        let resourcesURL = contentsURL.appendingPathComponent("Resources")
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: resourcesURL.path)
        else { return false }
        return entries.contains { $0.lowercased().contains(keyword) }
    }

    /// 主二进制内的构建路径特征计数（tauri / wails）。
    /// mmap 读取避免整块拷贝；超过 256MB 的主程序放弃扫描（收益递减）。
    private static func binaryKeywordScore(at url: URL) -> (tauri: Int, wails: Int)? {
        guard let plist = Bundle(url: url)?.infoDictionary,
              let executable = plist["CFBundleExecutable"] as? String else { return nil }
        let binaryURL = url.appendingPathComponent("Contents/MacOS/\(executable)")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: binaryURL.path),
              let size = attrs[.size] as? Int,
              size > 0, size <= 256 * 1024 * 1024,
              let data = try? Data(contentsOf: binaryURL, options: .mappedIfSafe)
        else { return nil }

        func occurrences(of needle: Data) -> Int {
            var count = 0
            var start = data.startIndex
            while let range = data.range(of: needle, options: [], in: start..<data.endIndex) {
                count += 1
                start = range.upperBound
            }
            return count
        }

        return (
            occurrences(of: Data("tauri".utf8)),
            occurrences(of: Data("wails".utf8))
        )
    }

    // MARK: 体积统计

    /// 递归累加目录内常规文件的分配大小
    public static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let en = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .fileSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in en {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .fileSizeKey]
            ), values.isRegularFile == true else { continue }
            total += Int64(values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }

    /// ~/Library 下用户数据：Application Support / Caches / Containers，
    /// 按 bundle id 与应用名双重匹配并去重
    static func userDataBytes(bundleID: String?, name: String) -> Int64 {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates: [URL] = []
        if let bid = bundleID, !bid.isEmpty {
            candidates += [
                home.appendingPathComponent("Library/Application Support/\(bid)"),
                home.appendingPathComponent("Library/Caches/\(bid)"),
                home.appendingPathComponent("Library/Containers/\(bid)")
            ]
        }
        candidates += [
            home.appendingPathComponent("Library/Application Support/\(name)"),
            home.appendingPathComponent("Library/Caches/\(name)")
        ]

        var seen = Set<URL>()
        var total: Int64 = 0
        let fm = FileManager.default
        for candidate in candidates {
            let std = candidate.standardizedFileURL
            guard seen.insert(std).inserted else { continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: std.path, isDirectory: &isDir), isDir.boolValue else { continue }
            total += directorySize(std)
        }
        return total
    }
}
