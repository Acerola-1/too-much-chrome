import XCTest
@testable import TooMuchChromeCore

/// 引导壳应用回归：/Applications 内只有微型引导器（无任何框架特征），
/// 真实客户端自更新到 ~/Library/Application Support/<名>/<名>.AppBundle/（Steam 布局），
/// 必须回退下钻检出真实客户端，而不是漏报
final class BootstrapShellTests: XCTestCase {

    private var tmp: URL!
    private var originalSupportRoot: URL!

    override func setUp() {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tmc-test-\(UUID().uuidString)")
        originalSupportRoot = AppScanner.appSupportRoot
        // 注入临时目录，避免命中真实 ~/Library/Application Support
        AppScanner.appSupportRoot = tmp.appendingPathComponent("Support")
    }

    override func tearDown() {
        AppScanner.appSupportRoot = originalSupportRoot
        try? FileManager.default.removeItem(at: tmp)
    }

    /// 最小 .app 夹具（与 AppScannerSelfTests 同款）
    private func makeApp(named name: String, bundleID: String) throws -> URL {
        let root = tmp.appendingPathComponent("\(name).app")
        let fm = FileManager.default
        for sub in ["Contents/MacOS", "Contents/Resources"] {
            try fm.createDirectory(
                at: root.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>\(bundleID)</string>
        <key>CFBundleExecutable</key><string>\(name)</string>
        <key>CFBundleName</key><string>\(name)</string>
        </dict></plist>
        """
        try plist.write(
            to: root.appendingPathComponent("Contents/Info.plist"),
            atomically: true, encoding: .utf8)
        try Data([0]).write(to: root.appendingPathComponent("Contents/MacOS/\(name)"))
        return root
    }

    func testSteamLikeBootstrapShellDetectsRelocatedCEFClient() throws {
        // 引导壳：Frameworks 空空如也（Steam.app 只有 Breakpad）
        let shell = try makeApp(named: "FakeSteam", bundleID: "com.example.fakesteam")

        // 真实客户端：Support/FakeSteam/FakeSteam.AppBundle/FakeSteam（无 .app 后缀），
        // Frameworks 内带 CEF——对应 Steam 的 Chromium Embedded Framework.framework
        let real = AppScanner.appSupportRoot
            .appendingPathComponent("FakeSteam/FakeSteam.AppBundle/FakeSteam")
        try FileManager.default.createDirectory(
            at: real.appendingPathComponent(
                "Contents/Frameworks/Chromium Embedded Framework.framework"),
            withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>com.example.fakesteam</string>
        <key>CFBundleName</key><string>FakeSteam</string>
        </dict></plist>
        """
        try plist.write(
            to: real.appendingPathComponent("Contents/Info.plist"),
            atomically: true, encoding: .utf8)

        let detected = try XCTUnwrap(AppScanner.detect(at: shell))
        XCTAssertEqual(detected.type, .cef)
        // 报告的路径应指向真实客户端而非引导壳
        XCTAssertEqual(detected.path, real.standardizedFileURL.path)
    }

    func testShellWithoutRelocationStillNotDetected() throws {
        // 无引导壳布局的普通应用不受回退影响
        let shell = try makeApp(named: "PlainShell", bundleID: "com.example.plainshell")
        XCTAssertNil(AppScanner.detect(at: shell))
    }
}
