import Foundation

// MARK: - 扫描器
// 检测分层见 detection-strategy.md：
//   Tier 1  Electron / CEF / NW.js（框架身份特征）+ 重命名引擎兜底（app.asar / 内嵌 Chromium UA）
//   Tier 3  完整浏览器（名称 / Bundle ID）
//   Tier 2  Tauri / Wails / Flutter WebView（关键词与二进制特征，实验性）
//   Tier 4  系统 WebView（WKWebView 承载 + 独立前端资源，实验性）
// 扫描路径：/Applications 与 ~/Applications 下两层 .app；
// 引导壳应用（如 Steam）的真实客户端在 ~/Library/Application Support 内，detect 时回退下钻

public enum AppScanner {

    /// 扫描器自身的 bundle id：其二进制内嵌检测关键词字面量（"wailsapp" 等），
    /// 扫描到自己必然误报 Wails，故永不报告自身（与 build-app.sh 的 BUNDLE_ID 保持一致）
    public static let ownBundleID = "com.acerola.too-much-chrome"

    /// Application Support 根（测试可注入临时目录，避免触碰真实用户数据）
    static var appSupportRoot: URL = FileManager.default
        .homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")

    /// 扫描根（测试可注入临时目录）
    static var scanRoots: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
    ]

    // MARK: 枚举候选

    /// 扫描根下**两层**枚举 .app：顶层，以及直接子目录内的应用
    /// （/Applications/Utilities/、~/Applications/<浏览器> Apps.localized/ 里 PWA 快捷方式）。
    /// 不进入 .app 内部——那里是 helper 子应用，不是独立安装的应用
    public static func candidateURLs() -> [URL] {
        let fm = FileManager.default
        var seen = Set<URL>()
        var urls: [URL] = []

        func collect(_ url: URL) {
            guard url.pathExtension == "app" else { return }
            let std = url.standardizedFileURL
            guard seen.insert(std).inserted else { return }
            urls.append(url)
        }

        func entries(of dir: URL) -> [URL] {
            (try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            )) ?? []
        }

        for dir in scanRoots {
            for entry in entries(of: dir) {
                if entry.pathExtension == "app" {
                    collect(entry)
                    continue
                }
                guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                else { continue }
                for sub in entries(of: entry) { collect(sub) }
            }
        }
        return urls.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    // MARK: 框架枚举

    /// 一个候选引擎框架：框架根、主二进制、主二进制体积。
    /// binary 为 nil 表示只有框架目录、解析不出主二进制（不完整/待更新的包）——
    /// 此时仍按名称与 plist 判定家族，只是拿不到二进制里的版本兜底信息
    struct FrameworkRef {
        let root: URL
        let binary: URL?
        let bytes: Int
    }

    /// Contents 下的引擎框架，按主二进制体积降序。
    /// 除 Contents/Frameworks 外还包含 Contents/<子目录>/<子应用>.app/Contents/Frameworks：
    /// 微信的 Chromium 内核（XWeb）在 Contents/MacOS/WeChatAppEx.app 内，顶层 Frameworks
    /// 最大的只是 50MB 级业务动态库——只看顶层会整片漏掉
    static func frameworks(in contentsURL: URL) -> [FrameworkRef] {
        let fm = FileManager.default
        var roots = [contentsURL.appendingPathComponent("Frameworks")]

        let topLevel = (try? fm.contentsOfDirectory(
            at: contentsURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        for entry in topLevel where entry.lastPathComponent != "Frameworks" {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                  let subs = try? fm.contentsOfDirectory(
                    at: entry, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            else { continue }
            for sub in subs where sub.pathExtension == "app" {
                roots.append(sub.appendingPathComponent("Contents/Frameworks"))
            }
        }

        var out: [FrameworkRef] = []
        for root in roots {
            for name in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] where name.hasSuffix(".framework") {
                let base = String(name.dropLast(".framework".count))
                let fw = root.appendingPathComponent(name)
                // 框架根的同名文件是指向 Versions/Current/<名> 的符号链接，两条路径都试
                let binary = [
                    fw.appendingPathComponent(base),
                    fw.appendingPathComponent("Versions/Current/\(base)")
                ].first { fm.fileExists(atPath: $0.path) }
                out.append(FrameworkRef(root: fw, binary: binary, bytes: binary.map(fileSize) ?? 0))
            }
        }
        return out.sorted { $0.bytes > $1.bytes }
    }

    /// 框架 plist 声明的版本（短版本优先，退回 build 号）
    static func declaredVersion(_ fw: FrameworkRef) -> String? {
        guard let info = Bundle(path: fw.root.path)?.infoDictionary else { return nil }
        let short = info["CFBundleShortVersionString"] as? String
        let build = info["CFBundleVersion"] as? String
        return [short, build].compactMap { $0 }.first { !$0.isEmpty }
    }

    /// 框架 plist 的 Bundle ID——改名构建（如 QQ 的 QQNT.framework、
    /// ChatGPT 的 Codex Framework.framework）仍可能保留 com.github.Electron.framework
    static func frameworkBundleID(_ fw: FrameworkRef) -> String? {
        Bundle(path: fw.root.path)?.infoDictionary?["CFBundleIdentifier"] as? String
    }

    // MARK: 引擎特征

    /// 内嵌 Chromium 引擎的框架主二进制体积下限。真实引擎是 100MB 量级
    /// （实测最小 128MB）；20MB 仅供排除小框架，避免无谓地映射大文件。
    /// 测试会下调此值以免造出几十 MB 的夹具
    static var engineFrameworkMinBytes = 20 * 1024 * 1024

    /// 引擎框架二进制读取上限（实测最大约 400MB）
    static let engineScanMaxBytes = 768 * 1024 * 1024

    /// Electron 版本：框架 plist 的版本落在 Electron 合理区间（1…锚+20）才采信。
    /// Electron 11（Chromium 87）这类老版本真实存在（实测 aTrust），不能因为小就丢弃；
    /// 超出区间说明写的是 Chromium 方案（实测 ChatGPT 的 "152.0.7977.83"）→ 用 UA 兜底
    static func electronVersion(declared: String?, framework: FrameworkRef) -> String? {
        if let m = VersionBands.major(declared),
           m >= 1, m <= VersionBands.builtInElectronMajor + VersionBands.electronMajorHeadroom {
            return declared
        }
        return framework.binary.flatMap { uaVersion(in: $0) }
    }

    /// CEF/Chromium 版本：框架 plist 常被厂商写成应用版本
    /// （实测网易云 "3.1.11" 而真实内核 116），低于可信下限时用 UA 兜底。
    /// 提不到就返回 nil——判"未知"，而不是拿厂商版本号去比 Chromium 锚点误报"老旧"
    static func chromiumVersion(declared: String?, framework: FrameworkRef) -> String? {
        if let m = VersionBands.major(declared), m >= VersionBands.chromiumMajorFloor {
            return declared
        }
        return framework.binary.flatMap { uaVersion(in: $0) }
    }

    /// 框架二进制内嵌的 Chromium UA 版本——即该框架实际携带的 Chromium 内核版本
    static func uaVersion(in binary: URL) -> String? {
        guard let data = mappedFile(binary, maxBytes: engineScanMaxBytes) else { return nil }
        return runtimeVersion(in: data, prefixes: ["Chrome/"])
    }

    /// Tier 1a：引擎框架的身份特征——目录名，或框架 plist 的 Bundle ID
    static func namedEngineHit(frameworks: [FrameworkRef]) -> (type: AppType, version: String?)? {
        for fw in frameworks {
            let lowered = fw.root.lastPathComponent.lowercased()
            if lowered.contains("electron framework")
                || frameworkBundleID(fw)?.lowercased() == "com.github.electron.framework" {
                return (.electron, electronVersion(declared: declaredVersion(fw), framework: fw))
            }
            if lowered.contains("chromium embedded") {
                return (.cef, chromiumVersion(declared: declaredVersion(fw), framework: fw))
            }
            if lowered.contains("nwjs") {
                return (.nwjs, nil)
            }
        }
        return nil
    }

    /// 引擎家族标记。全机普查：11 个真 Electron 框架的 `electron_browser` 命中 3–42、
    /// `ELECTRON_` 命中 6–27，两个真 CEF 框架的 `libcef` 命中 8–12、`CefBrowser` 命中 2–4，
    /// 两组互不误报。据此可把"带 Node"当成 Electron 的旧推理纠正掉——
    /// 微信 XWeb 三组标记全为 0，是腾讯自研的 Chromium 派生内核，既非 Electron 也非 CEF
    static let electronMarkers = ["electron_browser", "ELECTRON_"]
    static let cefMarkers = ["libcef", "CefBrowser"]

    static func engineFamily(in data: Data) -> AppType {
        if electronMarkers.contains(where: { dataContains(data, $0) }) { return .electron }
        if cefMarkers.contains(where: { dataContains(data, $0) }) { return .cef }
        return .vendorChromium
    }

    /// Tier 1b：重命名引擎兜底——框架名与 Bundle ID 都是厂商自有的构建，
    /// 只剩框架二进制自身可辨。先按家族标记定家族、用内嵌 `Chrome/x.y.z.w` UA 串定内核版本：
    /// - Electron（实测 ChatGPT：Codex Framework.framework / com.openai.codex.framework）
    /// - 自研内核（实测微信 XWeb：WeChatAppEx Framework / com.tencent.flue.framework，内核 144）
    static func rebrandedEngineHit(
        frameworks: [FrameworkRef], contentsURL: URL
    ) -> (type: AppType, version: String?)? {
        for fw in frameworks where fw.bytes >= engineFrameworkMinBytes {
            guard let binary = fw.binary,
                  let data = mappedFile(binary, maxBytes: engineScanMaxBytes),
                  let ua = runtimeVersion(in: data, prefixes: ["Chrome/"])
            else { continue }
            return (engineFamily(in: data), ua)
        }

        // 家族标记与 UA 都读不到时的最后兜底：app.asar 是 Electron 打包应用代码的档案。
        // 此时无从查证家族，按 Electron 记（asar 属 Electron 生态的默认假设，已在文档标注）
        if FileManager.default.fileExists(
            atPath: contentsURL.appendingPathComponent("Resources/app.asar").path
        ) {
            return (.electron, frameworks.first.flatMap {
                electronVersion(declared: declaredVersion($0), framework: $0)
            })
        }
        return nil
    }

    // MARK: Tier 4：系统 WebView

    /// 前端入口 HTML 文件名
    static let frontendEntryNames: Set<String> = ["index.html", "main.html", "app.html"]

    /// 文档目录名——帮助文档也常以 index.html 分发（实测 LibreOffice 的 Resources/help/）
    static let documentationDirNames: Set<String> = [
        "help", "docs", "documentation", "manual", "guide",
        "samples", "examples", "demos", "templates"
    ]

    /// 主二进制是否链接 WebKit.framework。Mach-O 的 LC_LOAD_DYLIB 原样保存安装路径，
    /// 故字符串命中与 `otool -L` 结果逐应用核对一致，无需起子进程
    static func linksWebKit(at url: URL) -> Bool {
        guard let data = mappedBinary(at: url) else { return false }
        return dataContains(data, "WebKit.framework/Versions")
    }

    /// 宿主是否携带 Safari App Extension。扩展的网页由 Safari 加载，不在宿主的 WebView 里，
    /// 这类容器的 Main.html 是扩展弹窗而非应用界面（实测 Microsoft Rewards for Safari、
    /// Doubao Extension 都是这种容器，且都带 Main.html + Script.js + Style.css）
    static func hostsAppExtension(contentsURL: URL) -> Bool {
        let plugins = contentsURL.appendingPathComponent("PlugIns")
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: plugins, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        return entries.contains { $0.pathExtension == "appex" }
    }

    /// Contents/Resources 及其一级子目录内是否有前端入口 HTML
    static func hasFrontendResources(contentsURL: URL) -> Bool {
        let fm = FileManager.default

        func scan(_ dir: URL, allowNested: Bool) -> Bool {
            let entries = (try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            )) ?? []
            for entry in entries {
                let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                guard isDir else {
                    if frontendEntryNames.contains(entry.lastPathComponent.lowercased()) { return true }
                    continue
                }
                guard allowNested,
                      !documentationDirNames.contains(entry.lastPathComponent.lowercased())
                else { continue }
                if scan(entry, allowNested: false) { return true }
            }
            return false
        }
        return scan(contentsURL.appendingPathComponent("Resources"), allowNested: true)
    }

    // MARK: Tier 2：Flutter WebView

    /// Flutter 的 macOS WebView 插件。Flutter 本身是自绘渲染，只有引入这类插件才承载网页；
    /// 纯 Flutter 应用（如终端、工具类）不算 Web 技术应用，故要求插件在架
    static let flutterWebViewPlugins = [
        "inappwebview", "webview_flutter", "desktop_webview_window", "flutter_webview"
    ]

    // MARK: 单应用检测

    public static func detect(at url: URL) -> DetectedApp? {
        detect(at: url, followRelocation: true)
    }

    private static func detect(at url: URL, followRelocation: Bool) -> DetectedApp? {
        let fm = FileManager.default
        let contentsURL = url.appendingPathComponent("Contents")

        let plist = Bundle(url: url)?.infoDictionary ?? [:]
        let name = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let bundleID = plist["CFBundleIdentifier"] as? String

        // 永不报告自身：自家二进制内嵌检测关键词，任何副本都会自命中
        if bundleID == ownBundleID || bundleID == Bundle.main.bundleIdentifier {
            return nil
        }
        let appVersion = (plist["CFBundleShortVersionString"] as? String)
            ?? (plist["CFBundleVersion"] as? String)

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

        func hit(_ type: AppType, _ version: String?) -> DetectedApp {
            build(type, version: version, status: VersionBands.status(for: type, version: version, latest: nil))
        }

        let frameworks = frameworks(in: contentsURL)

        // Tier 1a：自带 Chromium 内核的引擎框架（含保留 Electron Bundle ID 的改名构建）
        if let engine = namedEngineHit(frameworks: frameworks) {
            return hit(engine.type, engine.version)
        }

        // Tier 3：完整浏览器（仅列出）
        // Chromium 系浏览器的应用主版本与内核主版本对齐（Edge 79+ / Chrome / Opera / Vivaldi）；
        // 版本方案不对齐的（如 Arc 的 1.x）从主二进制的 "Chrome/x.y.z.w" UA 串兜底提取。
        // 必须排在重命名引擎兜底之前——Edge 框架里嵌的是过期的 Chrome/70 UA 串，
        // 先走 UA 会把浏览器误判成 Electron
        if isBrowser(name: name, bundleID: bundleID) {
            var engineVersion = appVersion
            if (VersionBands.major(appVersion) ?? 0) < VersionBands.chromiumMajorFloor {
                if let mapped = mappedBinary(at: url),
                   let ua = runtimeVersion(in: mapped, prefixes: ["Chrome/"]) {
                    engineVersion = ua
                }
            }
            return hit(.browser, engineVersion)
        }

        // Tier 1b：重命名引擎兜底（app.asar / 内嵌 Chromium UA）
        if let engine = rebrandedEngineHit(frameworks: frameworks, contentsURL: contentsURL) {
            return hit(engine.type, engine.version)
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
            return hit(.tauri, score?.tauriVersion ?? appVersion)
        }
        if wailsHit {
            return hit(.wails, score?.wailsVersion ?? appVersion)
        }

        // Tier 2b：Flutter + WebView 插件
        let frameworkEntries = (try? fm.contentsOfDirectory(
            atPath: contentsURL.appendingPathComponent("Frameworks").path)) ?? []
        let loweredEntries = frameworkEntries.map { $0.lowercased() }
        if loweredEntries.contains("fluttermacos.framework"),
           loweredEntries.contains(where: { entry in
               flutterWebViewPlugins.contains { entry.contains($0) }
           }) {
            return hit(.flutter, appVersion)
        }

        // 引导壳回退（Steam 最典型）：/Applications 里只有微型引导器，
        // 真实客户端自更新到 ~/Library/Application Support/<名>/<名>.AppBundle/，
        // 包根甚至不带 .app 后缀（Steam 即裸目录 Steam/）——本层特征全空时下钻再检
        if followRelocation,
           let relocated = relocatedBundle(for: name, bundleID: bundleID),
           let inner = detect(at: relocated.root, followRelocation: false) {
            // 数据口径修正：数据目录包含客户端本体（与 bodyBytes 重复计）
            // 与 steamapps 游戏安装内容（非 Chrome 内核，动辄数十 GB），均扣除
            let data = userDataBytes(
                bundleID: inner.bundleID, name: inner.name,
                excluding: [
                    relocated.root.deletingLastPathComponent(),
                    relocated.support.appendingPathComponent("steamapps")
                ]
            )
            return DetectedApp(
                name: inner.name,
                path: inner.path,
                bundleID: inner.bundleID,
                type: inner.type,
                version: inner.version,
                status: inner.status,
                bodyBytes: inner.bodyBytes,
                dataBytes: data
            )
        }

        // Tier 4：系统 WebView——链接 WebKit 且带独立前端资源。
        // 单看"链接了 WebKit"误报面太大（本机 80 个应用里 23 个命中，绝大多数
        // 只是拿 WebKit 做局部功能，如邮件预览、内嵌帮助）；加上"有前端入口 HTML"
        // 之后只剩真正的 WebView 承载型（实测 Typora：Resources/TypeMark/index.html）；
        // 再排掉 Safari 扩展宿主——它们的网页归 Safari 加载，不算应用自带的 WebView
        if !hostsAppExtension(contentsURL: contentsURL),
           linksWebKit(at: url),
           hasFrontendResources(contentsURL: contentsURL) {
            return hit(.systemWebView, appVersion)
        }

        return nil
    }

    /// 引导壳应用的真实客户端包根及其所在数据目录：
    /// ~/Library/Application Support/<名>/<名>.AppBundle/ 下任何带 Contents/Info.plist
    /// 的直接子目录；容器名依次尝试应用名与 Bundle ID
    private static func relocatedBundle(for name: String, bundleID: String?) -> (root: URL, support: URL)? {
        var dirNames = [name]
        if let bid = bundleID, !dirNames.contains(bid) { dirNames.append(bid) }
        let fm = FileManager.default
        for dirName in dirNames {
            let support = appSupportRoot.appendingPathComponent(dirName)
            let container = support.appendingPathComponent("\(dirName).AppBundle")
            guard let entries = try? fm.contentsOfDirectory(atPath: container.path) else { continue }
            for entry in entries.sorted() {
                let root = container.appendingPathComponent(entry)
                if fm.fileExists(atPath: root.appendingPathComponent("Contents/Info.plist").path) {
                    return (root, support)
                }
            }
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
        return mappedFile(
            url.appendingPathComponent("Contents/MacOS/\(executable)"),
            maxBytes: 256 * 1024 * 1024
        )
    }

    /// 文件真实体积。`attributesOfItem` 不跟随符号链接——框架根的同名文件是符号链接，
    /// 直接量会得到链接自身的 32 字节，把 300MB 的引擎判成小文件，
    /// 于是"体积 ≥20MB 才读"的引擎兜底永远不会触发
    static func fileSize(_ url: URL) -> Int {
        let target = url.resolvingSymlinksInPath()
        return (try? FileManager.default.attributesOfItem(atPath: target.path))?[.size] as? Int ?? 0
    }

    /// mmap 读取文件；超过 maxBytes 或读不到则返回 nil
    static func mappedFile(_ url: URL, maxBytes: Int) -> Data? {
        let target = url.resolvingSymlinksInPath()
        let size = fileSize(target)
        guard size > 0, size <= maxBytes else { return nil }
        return try? Data(contentsOf: target, options: .mappedIfSafe)
    }

    /// 字节流内是否含指定字符串
    static func dataContains(_ data: Data, _ needle: String) -> Bool {
        let needle = Data(needle.utf8)
        return data.range(of: needle, options: [], in: data.startIndex..<data.endIndex) != nil
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
    /// Saved Application State、Logs；按 bundle id 与应用名双重匹配并去重。
    /// excluding：位于数据目录内但不属于"用户数据"的子目录（如引导壳应用的
    /// 客户端本体、游戏安装内容），统计时扣除
    static func userDataBytes(bundleID: String?, name: String, excluding: [URL] = []) -> Int64 {
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
            var part = directorySize(std)
            for excluded in excluding {
                let ex = excluded.standardizedFileURL
                if ex.path.hasPrefix(std.path + "/"), fm.fileExists(atPath: ex.path) {
                    part -= directorySize(ex)
                }
            }
            total += part
        }
        return total
    }
}
