import Foundation

// MARK: - 扫描器
// 检测分层见 detection-strategy.md：Tier 1 Electron/CEF/NW.js（框架特征，高准确率）、
// Tier 3 完整浏览器（名称 / Bundle ID）、Tier 2 Tauri/Wails（关键词，实验性）、
// Tier 4 未知 WebView 默认关闭（误报风险高）。
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

        /// 框架 plist 的 Bundle ID——改名构建（如 QQ 的 QQNT.framework）
        /// 仍保留 com.github.Electron.framework，是目录名之外的第二特征
        func frameworkBundleID(_ index: Int) -> String? {
            Bundle(path: frameworksURL.appendingPathComponent(frameworkNames[index]).path)?
                .infoDictionary?["CFBundleIdentifier"] as? String
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
        // Electron 双特征：目录名（标准构建）或框架 plist Bundle ID
        // （com.github.Electron.framework，改名构建仍保留）
        let electronIndex = lowered.firstIndex(where: { $0.contains("electron framework") })
            ?? lowered.indices.first {
                frameworkBundleID($0)?.lowercased() == "com.github.electron.framework"
            }
        if let i = electronIndex {
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

        // Tier 3：完整浏览器（仅列出）
        // Chromium 系浏览器的应用主版本与内核主版本对齐（Edge 79+ / Chrome / Opera / Vivaldi）；
        // 版本方案不对齐的（如 Arc 的 1.x）从主二进制的 "Chrome/x.y.z.w" UA 串兜底提取
        if isBrowser(name: name, bundleID: bundleID) {
            var engineVersion = appVersion
            if (VersionBands.major(appVersion) ?? 0) < 20 {
                if let mapped = mappedBinary(at: url),
                   let ua = AppScanner.runtimeVersion(in: mapped, prefixes: ["Chrome/"]) {
                    engineVersion = ua
                }
            }
            return build(.browser, version: engineVersion, status: VersionBands.chromiumStatus(engineVersion))
        }

        // Tier 2：系统 WebView 框架（实验性）
        // Tauri release 构建不随包携带 tauri.conf.json（编译进二进制），
        // 可靠标记是二进制内的构建路径；Wails 靠 Go 模块路径（garble 混淆会抹掉，已知局限）
        var tauriHit = matchesKeyword("tauri", name: name, bundleID: bundleID, contentsURL: contentsURL)
        var wailsHit = matchesKeyword("wails", name: name, bundleID: bundleID, contentsURL: contentsURL)
        var score: BinaryScore? = nil
        if !tauriHit || !wailsHit {
            score = binaryKeywordScore(at: url)
            if let score {
                tauriHit = tauriHit || score.tauriSpecific >= 2
                    || (score.tauriRaw >= 5 && score.cargo >= 1)
                wailsHit = wailsHit || score.wailsapp >= 1 || score.wailsRaw >= 5
            }
        }
        if tauriHit {
            return build(.tauri, version: score?.tauriVersion ?? appVersion, status: .unknown)
        }
        if wailsHit {
            return build(.wails, version: score?.wailsVersion ?? appVersion, status: .unknown)
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

    /// 主二进制内的构建路径特征计数。
    /// mmap 读取避免整块拷贝；超过 256MB 的主程序放弃扫描（收益递减）。
    struct BinaryScore {
        let tauriRaw: Int        // 任意 "tauri"（含 centauri 之类的潜在误报面）
        let tauriSpecific: Int   // "src-tauri" + "tauri-"（cargo 路径上下文，近零误报）
        let cargo: Int           // ".cargo"（Rust 构建上下文）
        let wailsRaw: Int
        let wailsapp: Int        // "wailsapp"（github.com/wailsapp 模块路径）
        let tauriVersion: String?   // cargo 路径内嵌的 Tauri 运行时版本（如 2.10.3）
        let wailsVersion: String?  // Go module info 内嵌的 Wails 版本（如 2.11.0）
    }

    /// mmap 读取主二进制；超过 256MB 放弃（收益递减）
    static func mappedBinary(at url: URL) -> Data? {
        guard let plist = Bundle(url: url)?.infoDictionary,
              let executable = plist["CFBundleExecutable"] as? String else { return nil }
        let binaryURL = url.appendingPathComponent("Contents/MacOS/\(executable)")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: binaryURL.path),
              let size = attrs[.size] as? Int,
              size > 0, size <= 256 * 1024 * 1024,
              let data = try? Data(contentsOf: binaryURL, options: .mappedIfSafe)
        else { return nil }
        return data
    }

    private static func binaryKeywordScore(at url: URL) -> BinaryScore? {
        guard let data = mappedBinary(at: url) else { return nil }

        func occurrences(of needle: String) -> Int {
            let needle = Data(needle.utf8)
            var count = 0
            var start = data.startIndex
            while let range = data.range(of: needle, options: [], in: start..<data.endIndex) {
                count += 1
                start = range.upperBound
            }
            return count
        }

        return BinaryScore(
            tauriRaw: occurrences(of: "tauri"),
            tauriSpecific: occurrences(of: "src-tauri") + occurrences(of: "tauri-"),
            cargo: occurrences(of: ".cargo"),
            wailsRaw: occurrences(of: "wails"),
            wailsapp: occurrences(of: "wailsapp"),
            tauriVersion: runtimeVersion(
                in: data,
                // "tauri-2.10.3/src/…"；"tauri-plugin-x" 因紧跟非数字自动跳过
                prefixes: ["tauri-"]
            ),
            wailsVersion: runtimeVersion(
                in: data,
                // Go module info："github.com/wailsapp/wails/v2 v2.11.0" 或 "…/wails/v2@v2.11.0"
                prefixes: ["wails/v2 v", "wailsapp/wails/v2 v", "wails/v2@v", "wailsapp/wails@v"]
            )
        )
    }

    /// 在字节流中查找 "前缀 + x.y.z" 形态的版本号（紧随前缀的必须是数字，
    /// 且至少包含一个点与两位数字）；逐个候选扫描直到命中。
    /// 上限 20 字节，容纳 Chrome UA 的四段版本（如 151.0.4129.61）
    public static func runtimeVersion(in data: Data, prefixes: [String]) -> String? {
        for prefix in prefixes {
            let needle = Data(prefix.utf8)
            var start = data.startIndex
            while let range = data.range(of: needle, options: [], in: start..<data.endIndex) {
                var index = range.upperBound
                var bytes: [UInt8] = []
                while index < data.endIndex, bytes.count < 20 {
                    let byte = data[index]
                    guard (48...57).contains(byte) || byte == 46 else { break }
                    bytes.append(byte)
                    index = data.index(after: index)
                }
                if let candidate = String(bytes: bytes, encoding: .utf8),
                   let first = candidate.first, first.isNumber,
                   candidate.contains("."),
                   candidate.filter(\.isNumber).count >= 2 {
                    return candidate
                }
                start = range.upperBound
            }
        }
        return nil
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
    /// 以及 WebKit（WKWebView 数据，Tauri/Wails 的主要落盘处）、
    /// Saved Application State、Logs；按 bundle id 与应用名双重匹配并去重
    static func userDataBytes(bundleID: String?, name: String) -> Int64 {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates: [URL] = []
        if let bid = bundleID, !bid.isEmpty {
            candidates += [
                home.appendingPathComponent("Library/Application Support/\(bid)"),
                home.appendingPathComponent("Library/Caches/\(bid)"),
                home.appendingPathComponent("Library/Containers/\(bid)"),
                home.appendingPathComponent("Library/WebKit/\(bid)"),
                home.appendingPathComponent("Library/Saved Application State/\(bid).savedState"),
                home.appendingPathComponent("Library/Logs/\(bid)")
            ]
        }
        candidates += [
            home.appendingPathComponent("Library/Application Support/\(name)"),
            home.appendingPathComponent("Library/Caches/\(name)"),
            home.appendingPathComponent("Library/Logs/\(name)")
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
