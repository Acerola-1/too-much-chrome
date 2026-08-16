import XCTest
@testable import TooMuchChromeCore

/// 版本带判定回归测试：厂商塞入的应用版本应判"未知"而非"老旧"（2026-08 校准锚）
final class VersionBandsTests: XCTestCase {

    // MARK: Electron（锚定 latest = 43，2026-08）

    func testElectronCurrentBand() {
        XCTAssertEqual(VersionBands.electronStatus("43.4.0"), .current)
        XCTAssertEqual(VersionBands.electronStatus("41.0.0"), .current)
    }

    func testElectronOkBand() {
        XCTAssertEqual(VersionBands.electronStatus("40.2.1"), .ok)
        XCTAssertEqual(VersionBands.electronStatus("36.0.0"), .ok)
    }

    func testElectronAgingAndOutdatedBands() {
        XCTAssertEqual(VersionBands.electronStatus("35.1.4"), .aging)
        XCTAssertEqual(VersionBands.electronStatus("31.0.0"), .aging)
        XCTAssertEqual(VersionBands.electronStatus("30.4.0"), .outdated)
        XCTAssertEqual(VersionBands.electronStatus("22.0.0"), .outdated)
        // <20 的版本号触发合理性防线 → 未知
        XCTAssertEqual(VersionBands.electronStatus("11.5.0"), .unknown)
    }

    // MARK: 厂商污染版本号 → 未知（不许误判"老旧"）

    func testVendorStampedVersionIsUnknown() {
        // NeteaseMusic 把应用版本 3.1.10 塞进 CEF 框架 plist；aTrust 塞 11.5.0
        XCTAssertEqual(VersionBands.chromiumStatus("3.1.10"), .unknown)
        XCTAssertEqual(VersionBands.electronStatus("1.2.3"), .unknown)
        XCTAssertEqual(VersionBands.electronStatus(nil), .unknown)
        XCTAssertEqual(VersionBands.electronStatus(""), .unknown)
    }

    // MARK: CEF / Chromium（锚定 latest = 151，2026-08）

    func testChromiumBands() {
        XCTAssertEqual(VersionBands.chromiumStatus("151.0.7922"), .current)
        XCTAssertEqual(VersionBands.chromiumStatus("148.0.0"), .current)
        XCTAssertEqual(VersionBands.chromiumStatus("142.0.57.02"), .ok)
        XCTAssertEqual(VersionBands.chromiumStatus("138.0.0"), .aging)
        XCTAssertEqual(VersionBands.chromiumStatus("120.0.0"), .outdated)
    }

    // MARK: 大版本解析健壮性

    func testMajorParsing() {
        XCTAssertEqual(VersionBands.major("40.0.0"), 40)
        // 数字过滤使 "v33.2.0" 宽容解析为 33（厂商前缀容忍）
        XCTAssertEqual(VersionBands.major("v33.2.0"), 33)
        XCTAssertEqual(VersionBands.major(nil), nil)
    }

    // MARK: 动态基准（在线 latestMajor 覆盖内置锚）

    func testElectronDynamicBaseline() {
        // 内置锚 43：40 属 ok；换在线锚 45：40 仍 ok、44 变 current、37 变 aging
        XCTAssertEqual(VersionBands.electronStatus("40.0.0"), .ok)
        XCTAssertEqual(VersionBands.electronStatus("40.0.0", latestMajor: 45), .ok)
        XCTAssertEqual(VersionBands.electronStatus("44.0.0", latestMajor: 45), .current)
        XCTAssertEqual(VersionBands.electronStatus("37.0.0", latestMajor: 45), .aging)
    }

    // MARK: Tauri / Wails 运行时分档

    func testRuntimeStatusBands() {
        XCTAssertEqual(VersionBands.tauriStatus("2.10.3", latest: "2.10.3"), .current)
        XCTAssertEqual(VersionBands.tauriStatus("2.10.3", latest: "2.12.0"), .current)   // 次版本差 ≤2
        XCTAssertEqual(VersionBands.tauriStatus("2.6.0", latest: "2.12.0"), .ok)         // 差 3–6
        XCTAssertEqual(VersionBands.tauriStatus("2.2.0", latest: "2.12.0"), .aging)      // 差 >6
        XCTAssertEqual(VersionBands.tauriStatus("1.30.0", latest: "2.12.0"), .aging)     // 落后 1 个主版本
        XCTAssertEqual(VersionBands.wailsStatus("2.11.0", latest: "2.12.1"), .current)
        XCTAssertEqual(VersionBands.wailsStatus("2.4.0", latest: "2.12.1"), .aging)
        // 无基准不判定
        XCTAssertEqual(VersionBands.tauriStatus("2.10.3", latest: nil), .unknown)
    }

    // MARK: 浏览器（Chromium 系）引擎分档

    func testBrowserEngineBanding() {
        // Edge/Chrome/Opera/Vivaldi 应用主版本 == Chromium 内核主版本
        XCTAssertEqual(VersionBands.chromiumStatus("151.0.4129.61", latestMajor: 152), .current)
        XCTAssertEqual(VersionBands.chromiumStatus("140.0.0", latestMajor: 152), .ok)
        // 非对齐版本方案（如 Arc 的 1.x）→ 合理性防线判未知，交由 UA 提取兜底
        XCTAssertEqual(VersionBands.chromiumStatus("1.87.0", latestMajor: 152), .unknown)
    }

    func testChromeUAExtraction() {
        let ua = Data("Mozilla/5.0 … Chrome/151.0.4129.61 Safari/537.36 Edg/151.0.4129.61".utf8)
        XCTAssertEqual(AppScanner.runtimeVersion(in: ua, prefixes: ["Chrome/"]), "151.0.4129.61")
    }

    // MARK: 二进制运行时版本提取

    func testRuntimeVersionExtraction() {
        let cargo = Data("registry/src/index.crates.io-xxx/tauri-2.10.3/src/lib.rs".utf8)
        XCTAssertEqual(AppScanner.runtimeVersion(in: cargo, prefixes: ["tauri-"]), "2.10.3")

        // "tauri-plugin-shell" 紧跟非数字，应跳过并继续找下一个候选
        let mixed = Data("…tauri-plugin-shell/src + tauri-2.9.4/build…".utf8)
        XCTAssertEqual(AppScanner.runtimeVersion(in: mixed, prefixes: ["tauri-"]), "2.9.4")

        // Go module info 形态
        let go = Data("github.com/wailsapp/wails/v2 v2.11.0 h1:abc".utf8)
        XCTAssertEqual(
            AppScanner.runtimeVersion(in: go, prefixes: ["wails/v2 v", "wails/v2@v"]),
            "2.11.0"
        )

        // 无匹配
        XCTAssertNil(AppScanner.runtimeVersion(in: Data("hello world".utf8), prefixes: ["tauri-"]))
    }
}
