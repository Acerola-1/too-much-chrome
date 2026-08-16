import XCTest
@testable import TooMuchChromeCore

/// detect 的自检测回归：扫描器二进制内嵌 "wailsapp"/"tauri-" 等关键词字面量，
/// 扫描自身（任意副本）时必然自命中——必须按 bundle id 跳过，永不报告自己
final class AppScannerSelfTests: XCTestCase {

    private var tmp: URL!

    override func setUp() {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tmc-tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmp)
    }

    /// 构造最小 .app 夹具：Info.plist + 主二进制（可注入关键词字节）
    private func makeApp(named name: String, bundleID: String, binaryStrings: [String]) throws -> URL {
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
        <key>CFBundleShortVersionString</key><string>0.1.0</string>
        </dict></plist>
        """
        try plist.write(
            to: root.appendingPathComponent("Contents/Info.plist"),
            atomically: true, encoding: .utf8)
        let blob = (["com.example.filler.padding"] + binaryStrings)
            .joined(separator: "\0")
        try Data(blob.utf8).write(to: root.appendingPathComponent("Contents/MacOS/\(name)"))
        return root
    }

    func testNeverReportsItself() throws {
        // 二进制含 "wailsapp"（模拟扫描器自身的关键词字面量），但 bundle id 是自己 → 跳过
        let app = try makeApp(
            named: "TooMuchChrome", bundleID: AppScanner.ownBundleID,
            binaryStrings: ["wailsapp/wails/v2 v2.11.0", "src-tauri", ".cargo"])
        XCTAssertNil(AppScanner.detect(at: app))
    }

    func testOtherAppWithWailsSignatureStillDetected() throws {
        // 同样的关键词字节，但属于第三方应用 → 正常命中 Wails
        let app = try makeApp(
            named: "SomeWailsApp", bundleID: "com.example.somewails",
            binaryStrings: ["wailsapp/wails/v2 v2.11.0"])
        let detected = try XCTUnwrap(AppScanner.detect(at: app))
        XCTAssertEqual(detected.type, .wails)
    }

    func testPlainAppNotDetected() throws {
        let app = try makeApp(named: "Plain", bundleID: "com.example.plain", binaryStrings: [])
        XCTAssertNil(AppScanner.detect(at: app))
    }
}
