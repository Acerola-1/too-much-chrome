import XCTest
@testable import TooMuchChromeCore

/// 版本带判定回归测试。
/// 内置锚：Electron 44 / Chromium 152（2026-09 校准：npm registry 与 Google VersionHistory 实查）
final class VersionBandsTests: XCTestCase {

    // MARK: Electron（锚 44 → 当前 ≥42 · 正常 ≥37 · 建议更新 ≥32 · 更早老旧）

    func testElectronCurrentBand() {
        XCTAssertEqual(VersionBands.electronStatus("44.3.0"), .current)
        XCTAssertEqual(VersionBands.electronStatus("42.0.0"), .current)
    }

    func testElectronOkBand() {
        XCTAssertEqual(VersionBands.electronStatus("41.0.0"), .ok)
        XCTAssertEqual(VersionBands.electronStatus("37.0.0"), .ok)
    }

    func testElectronAgingAndOutdatedBands() {
        XCTAssertEqual(VersionBands.electronStatus("35.1.4"), .aging)
        XCTAssertEqual(VersionBands.electronStatus("32.0.0"), .aging)
        XCTAssertEqual(VersionBands.electronStatus("31.0.0"), .outdated)
        XCTAssertEqual(VersionBands.electronStatus("22.0.0"), .outdated)
    }

    // MARK: 老版本 Electron 不能被当成"版本号被污染"

    /// aTrust 的框架 plist 写 11.5.0——那是**真实**的 Electron 11（Chromium 87，实测 UA 串佐证）。
    /// 旧实现用"大版本 ≥20"当合理性防线，把它误判成"未知"，等于把明显该更新的引擎放过了
    func testGenuinelyOldElectronJudgedOutdatedNotUnknown() {
        XCTAssertEqual(VersionBands.electronStatus("11.5.0"), .outdated)
        XCTAssertEqual(VersionBands.electronStatus("1.2.3"), .outdated)
    }

    // MARK: 框架 plist 写成 Chromium 方案 → 按 Chromium 分档

    /// ChatGPT 的框架被改名后版本写成 "152.0.7977.83"。152 不是 Electron 大版本，
    /// 拿它比 Electron 锚点只是碰巧也对，得改走 Chromium 阈值才自洽
    func testChromiumSchemeVersionInsideElectronFramework() {
        XCTAssertEqual(VersionBands.electronStatus("152.0.7977.83"), .current)
        XCTAssertEqual(VersionBands.electronStatus("120.0.0"), .outdated)
    }

    // MARK: CEF/Chromium 版本号被污染 → 未知（不许误判"老旧"）

    func testVendorStampedVersionIsUnknown() {
        // 网易云把应用版本 3.1.11 塞进 CEF 框架 plist；低于 Chromium 可信下限即拒收，
        // 交由 AppScanner 用框架二进制里的 UA 串兜底
        XCTAssertEqual(VersionBands.chromiumStatus("3.1.10"), .unknown)
        XCTAssertEqual(VersionBands.electronStatus(nil), .unknown)
        XCTAssertEqual(VersionBands.electronStatus(""), .unknown)
        XCTAssertEqual(VersionBands.electronStatus("0.0.0"), .unknown)
    }

    // MARK: CEF / Chromium（锚 152 → 当前 ≥149 · 正常 ≥140 · 建议更新 ≥129 · 更早老旧）

    func testChromiumBands() {
        XCTAssertEqual(VersionBands.chromiumStatus("152.0.7977"), .current)
        XCTAssertEqual(VersionBands.chromiumStatus("149.0.0"), .current)
        XCTAssertEqual(VersionBands.chromiumStatus("148.0.0"), .ok)
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
        // 内置锚 44：40 属 ok；换在线锚 45：40 仍 ok、44 变 current、37 变 aging
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
