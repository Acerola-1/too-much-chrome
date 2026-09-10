import XCTest
@testable import TooMuchChromeCore

/// 重命名引擎与新增分层的回归测试。
/// 每个用例对应一类真机实测过的漏检/误报，夹具按真机布局搭出来：
/// 框架走完整的 Versions/Current + 根符号链接结构，
/// 顺带覆盖"框架主二进制是符号链接、必须先解析才能量出体积"这个坑
final class RenamedEngineTests: XCTestCase {

    private var tmp: URL!
    private var originalMinBytes = 0
    private var originalScanRoots: [URL] = []

    override func setUp() {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tmc-engine-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        originalMinBytes = AppScanner.engineFrameworkMinBytes
        originalScanRoots = AppScanner.scanRoots
        AppScanner.engineFrameworkMinBytes = 0   // 夹具二进制只有几十字节
    }

    override func tearDown() {
        AppScanner.engineFrameworkMinBytes = originalMinBytes
        AppScanner.scanRoots = originalScanRoots
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: 夹具

    @discardableResult
    private func makeApp(
        named name: String, bundleID: String, version: String? = "1.0.0", binary: String = ""
    ) throws -> URL {
        let root = tmp.appendingPathComponent("\(name).app")
        try writeAppBundle(at: root, name: name, bundleID: bundleID, version: version, binary: binary)
        return root
    }

    private func writeAppBundle(
        at root: URL, name: String, bundleID: String, version: String?, binary: String
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        var body = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>\(bundleID)</string>
        <key>CFBundleExecutable</key><string>\(name)</string>
        <key>CFBundleName</key><string>\(name)</string>
        """
        if let version {
            body += "\n<key>CFBundleShortVersionString</key><string>\(version)</string>"
        }
        body += "\n</dict></plist>\n"
        try body.write(to: root.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)
        try Data(binary.utf8).write(to: root.appendingPathComponent("Contents/MacOS/\(name)"))
    }

    /// 真实 macOS 框架布局：Versions/A/<名> + Versions/Current + 根符号链接
    @discardableResult
    private func addFramework(
        to app: URL, named framework: String, bundleID: String, version: String, binary: String
    ) throws -> URL {
        let fm = FileManager.default
        let root = app.appendingPathComponent("Contents/Frameworks/\(framework).framework")
        let versioned = root.appendingPathComponent("Versions/A")
        try fm.createDirectory(at: versioned.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        try Data(binary.utf8).write(to: versioned.appendingPathComponent(framework))
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>\(bundleID)</string>
        <key>CFBundleShortVersionString</key><string>\(version)</string>
        <key>CFBundleVersion</key><string>\(version)</string>
        <key>CFBundleExecutable</key><string>\(framework)</string>
        </dict></plist>
        """
        try plist.write(to: versioned.appendingPathComponent("Resources/Info.plist"), atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(
            atPath: root.appendingPathComponent("Versions/Current").path, withDestinationPath: "A")
        try fm.createSymbolicLink(
            atPath: root.appendingPathComponent(framework).path,
            withDestinationPath: "Versions/Current/\(framework)")
        try fm.createSymbolicLink(
            atPath: root.appendingPathComponent("Resources").path, withDestinationPath: "Versions/Current/Resources")
        return root
    }

    /// 只有目录、没有主二进制的框架（用于 Flutter 插件这类只按名称判定的情况）
    private func addEmptyFramework(to app: URL, named framework: String) throws {
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents/Frameworks/\(framework).framework"),
            withIntermediateDirectories: true)
    }

    private func write(_ relativePath: String, to app: URL, content: String = "x") throws {
        let url = app.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
    }

    // MARK: 重命名引擎兜底（框架名与 Bundle ID 双双被改）

    /// ChatGPT：Codex Framework.framework / com.openai.codex.framework。
    /// 家族由框架二进制里的 Electron 标记认定，与 app.asar 无关
    func testRenamedElectronDetectedByFrameworkMarkers() throws {
        let app = try makeApp(named: "FakeGPT", bundleID: "com.example.codex")
        try addFramework(
            to: app, named: "Codex Framework", bundleID: "com.example.codex.framework",
            version: "152.0.7977.83", binary: "…electron_browser…ELECTRON_…Chrome/152.0.7977.83…")
        try write("Contents/Resources/app.asar", to: app)

        let detected = try XCTUnwrap(AppScanner.detect(at: app))
        XCTAssertEqual(detected.type, .electron)
        XCTAssertEqual(detected.version, "152.0.7977.83")
        // 152 是 Chromium 方案而非 Electron 大版本，必须按 Chromium 分档——
        // 真正的陷阱是把 Modern 判成老旧
        XCTAssertNotEqual(detected.status, .outdated)
    }

    /// app.asar 是家族标记读不到时的兜底：仅凭它存在即按 Electron 记
    func testAsarAloneFallsBackToElectron() throws {
        let app = try makeApp(named: "FakeAsarOnly", bundleID: "com.example.asar")
        try addFramework(
            to: app, named: "Mystery Engine", bundleID: "com.example.mystery",
            version: "1.2.3", binary: "no markers here")
        try write("Contents/Resources/app.asar", to: app)

        XCTAssertEqual(try XCTUnwrap(AppScanner.detect(at: app)).type, .electron)
    }

    /// 微信 XWeb：WeChatAppEx Framework / com.tencent.flue.framework / 版本 4.1.13，
    /// 名字、Bundle ID、版本三样都是厂商自有的，且**既非 Electron 也非 CEF**——
    /// 三组家族标记全为 0（实测 node:: 192 但 electron_browser / ELECTRON_ / libcef 均为 0），
    /// 判为厂商自研的 Chromium 派生内核。带 Node 不等于 Electron
    func testSelfBuiltChromiumIsNotLabelledElectron() throws {
        let app = try makeApp(named: "FakeWeChat", bundleID: "com.example.xinwechat")
        try addFramework(
            to: app, named: "WeChatAppEx Framework", bundleID: "com.tencent.flue.framework",
            version: "4.1.13", binary: "…blink…node::…content::…Chrome/144.0.7559.236…")
        try write("Contents/Resources/app.html.bak", to: app)   // 无关资源，不应影响判定

        let detected = try XCTUnwrap(AppScanner.detect(at: app))
        XCTAssertEqual(detected.type, .vendorChromium)
        XCTAssertEqual(detected.version, "144.0.7559.236")
        XCTAssertEqual(detected.status, .ok)
    }

    func testRenamedCEFDetectedByFrameworkMarkers() throws {
        let app = try makeApp(named: "FakeShell", bundleID: "com.example.shell")
        try addFramework(
            to: app, named: "Vendor Engine", bundleID: "com.vendor.engine",
            version: "7.2.1", binary: "…libcef…CefBrowser…Chrome/130.0.6723.58…")

        let detected = try XCTUnwrap(AppScanner.detect(at: app))
        XCTAssertEqual(detected.type, .cef)
        XCTAssertEqual(detected.version, "130.0.6723.58")
    }

    // MARK: 嵌套子应用里的引擎（微信在 Contents/MacOS、WPS 在 Contents/SharedSupport）

    func testEngineNestedInSubAppIsFound() throws {
        let app = try makeApp(named: "FakeOffice", bundleID: "com.example.office")
        let sub = app.appendingPathComponent("Contents/SharedSupport/browserserver.app")
        try writeAppBundle(at: sub, name: "browserserver", bundleID: "com.example.browserserver", version: "1", binary: "")
        try addFramework(
            to: sub, named: "Chromium Embedded Framework", bundleID: "org.chromium.cef",
            version: "126.0.0.0", binary: "Chrome/126.0.6478.126")

        let detected = try XCTUnwrap(AppScanner.detect(at: app))
        XCTAssertEqual(detected.type, .cef)
        XCTAssertEqual(detected.version, "126.0.0.0")
    }

    // MARK: 版本号可信度（厂商版本 vs 真实内核版本）

    /// 网易云：CEF 框架 plist 被写成应用版本 3.1.11，真实内核 116 —— 必须用 UA 兜底，
    /// 否则要么判"未知"（旧行为），要么误判成 Chromium 3
    func testVendorVersionInCEFFallsBackToUA() throws {
        let app = try makeApp(named: "FakeMusic", bundleID: "com.example.music")
        try addFramework(
            to: app, named: "Chromium Embedded Framework", bundleID: "org.chromium.cef",
            version: "3.1.11", binary: "Chrome/116.0.5845.190")

        let detected = try XCTUnwrap(AppScanner.detect(at: app))
        XCTAssertEqual(detected.version, "116.0.5845.190")
        XCTAssertEqual(detected.status, .outdated)
    }

    /// aTrust：Electron 框架 plist 的 11.5.0 是**真实**的 Electron 11（内核 Chromium 87）。
    /// 大版本小不等于版本号被污染——不能因此丢掉版本判成"未知"
    func testGenuinelyOldElectronVersionIsKept() throws {
        let app = try makeApp(named: "FakeVPN", bundleID: "com.example.vpn")
        try addFramework(
            to: app, named: "Electron Framework", bundleID: "com.github.Electron.framework",
            version: "11.5.0", binary: "Chrome/87.0.4280.141")

        let detected = try XCTUnwrap(AppScanner.detect(at: app))
        XCTAssertEqual(detected.type, .electron)
        XCTAssertEqual(detected.version, "11.5.0")
        XCTAssertEqual(detected.status, .outdated)
    }

    // MARK: Tier 4：系统 WebView（WKWebView 承载 + 独立前端资源）

    private func makeWebKitHost(named name: String) throws -> URL {
        let app = try makeApp(
            named: name, bundleID: "com.example.\(name.lowercased())",
            binary: "…/System/Library/Frameworks/WebKit.framework/Versions/A/WebKit…")
        return app
    }

    /// Typora：不自带 Chromium 内核，但整个界面由 WKWebView 承载前端目录
    func testWebKitHostWithFrontendDirectoryDetected() throws {
        let app = try makeWebKitHost(named: "FakeTypora")
        try write("Contents/Resources/TypeMark/index.html", to: app)

        let detected = try XCTUnwrap(AppScanner.detect(at: app))
        XCTAssertEqual(detected.type, .systemWebView)
    }

    func testWebKitHostWithoutFrontendNotDetected() throws {
        let app = try makeWebKitHost(named: "FakeNative")
        XCTAssertNil(AppScanner.detect(at: app))
    }

    /// 帮助文档也常以 index.html 分发（实测 LibreOffice 的 Resources/help/），不算应用界面
    func testWebKitHostWithDocumentationHTMLNotDetected() throws {
        let app = try makeWebKitHost(named: "FakeDocs")
        try write("Contents/Resources/help/index.html", to: app)
        XCTAssertNil(AppScanner.detect(at: app))
    }

    /// Safari 扩展宿主：网页由 Safari 加载，不在宿主自己的 WebView 里
    /// （实测 Microsoft Rewards for Safari / Doubao Extension 都带 Main.html）
    func testAppExtensionHostNotDetected() throws {
        let app = try makeWebKitHost(named: "FakeRewards")
        try write("Contents/Resources/Main.html", to: app)
        try write("Contents/PlugIns/FakeRewards Extension.appex/Contents/Info.plist", to: app)
        XCTAssertNil(AppScanner.detect(at: app))
    }

    func testFrontendWithoutWebKitNotDetected() throws {
        let app = try makeApp(named: "FakePlain", bundleID: "com.example.plain")
        try write("Contents/Resources/app/index.html", to: app)
        XCTAssertNil(AppScanner.detect(at: app))
    }

    // MARK: Tier 2：Flutter WebView

    func testFlutterWithWebViewPluginDetected() throws {
        let app = try makeApp(named: "FakeFlutterWeb", bundleID: "com.example.flutterweb")
        try addEmptyFramework(to: app, named: "FlutterMacOS")
        try addEmptyFramework(to: app, named: "flutter_inappwebview_macos")

        let detected = try XCTUnwrap(AppScanner.detect(at: app))
        XCTAssertEqual(detected.type, .flutter)
    }

    /// 纯 Flutter 是自绘渲染，不承载网页——没有 webview 插件就不该算 Web 技术应用
    func testFlutterWithoutWebViewPluginNotDetected() throws {
        let app = try makeApp(named: "FakeFlutterNative", bundleID: "com.example.flutternative")
        try addEmptyFramework(to: app, named: "FlutterMacOS")
        try addEmptyFramework(to: app, named: "sqflite")
        XCTAssertNil(AppScanner.detect(at: app))
    }

    // MARK: 枚举深度（/Applications/Utilities 与 <浏览器> Apps.localized 里的快捷方式）

    func testCandidateURLsIncludeSecondLevelApps() throws {
        let root = tmp.appendingPathComponent("Apps")
        let direct = root.appendingPathComponent("Direct.app")
        let nested = root.appendingPathComponent("Utilities/Nested.app")
        try writeAppBundle(at: direct, name: "Direct", bundleID: "com.example.direct", version: "1", binary: "")
        try writeAppBundle(at: nested, name: "Nested", bundleID: "com.example.nested", version: "1", binary: "")

        AppScanner.scanRoots = [root]
        let names = AppScanner.candidateURLs().map(\.lastPathComponent)
        XCTAssertTrue(names.contains("Direct.app"))
        XCTAssertTrue(names.contains("Nested.app"))

        // 不进入 .app 内部：helper 子应用不是独立安装的应用
        let helper = direct.appendingPathComponent("Contents/Frameworks/Helper.app")
        try writeAppBundle(at: helper, name: "Helper", bundleID: "com.example.helper", version: "1", binary: "")
        XCTAssertFalse(AppScanner.candidateURLs().map(\.lastPathComponent).contains("Helper.app"))
    }
}
