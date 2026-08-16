import Foundation
import TooMuchChromeCore

// tmc-scan：无头扫描 CLI，验证检测与体积统计
// 用法：
//   swift run tmc-scan            离线（用内置/缓存基准）
//   swift run tmc-scan --online   在线拉取各框架最新版基准并动态分档

let online = CommandLine.arguments.contains("--online")
let semaphore = DispatchSemaphore(value: 0)

Task.detached(priority: .userInitiated) {
    // 在线基准先就位（与扫描并发无依赖，串行简单直观）
    var baseline: VersionBaseline? = nil
    if online {
        baseline = await VersionCatalog.refresh()
        print("版本基准 · \(baseline!.sourceText)：\(baseline!.summaryText)\n")
    }

    let urls = AppScanner.candidateURLs()
    print("枚举到 \(urls.count) 个 .app，开始检测…\n")

    func statusMark(_ app: DetectedApp) -> String {
        let status: VersionStatus
        switch app.type {
        case .electron:
            status = VersionBands.electronStatus(app.version, latestMajor: baseline?.electronMajor)
        case .cef, .browser:
            status = VersionBands.chromiumStatus(app.version, latestMajor: baseline?.chromiumMajor)
        case .tauri:
            status = VersionBands.tauriStatus(app.version, latest: baseline?.tauriVersion)
        case .wails:
            status = VersionBands.wailsStatus(app.version, latest: baseline?.wailsVersion)
        case .nwjs:
            status = .unknown
        }
        switch status {
        case .current, .ok: return "✅"
        case .aging: return "⚠️ "
        case .outdated: return "🔴"
        case .unknown: return "❓"
        }
    }

    var found: [DetectedApp] = []
    for (index, url) in urls.enumerated() {
        if let app = AppScanner.detect(at: url) {
            found.append(app)
            print(
                "\(app.type.label.padding(toLength: 9, withPad: " ", startingAt: 0))"
                    + "\(statusMark(app)) "
                    + "\(app.name.padding(toLength: 24, withPad: " ", startingAt: 0))"
                    + "v\((app.version ?? "-").padding(toLength: 10, withPad: " ", startingAt: 0))"
                    + "\(fmt(app.bodyBytes).padding(toLength: 9, withPad: " ", startingAt: 0))"
                    + "本体 "
                    + "\(fmt(app.dataBytes).padding(toLength: 9, withPad: " ", startingAt: 0))"
                    + "数据"
            )
        }
        if (index + 1) % 20 == 0 {
            print("  … 已检查 \(index + 1)/\(urls.count)")
        }
    }

    let body = found.reduce(Int64(0)) { $0 + $1.bodyBytes }
    let data = found.reduce(Int64(0)) { $0 + $1.dataBytes }
    print("\n合计：\(found.count) 个 WebView 应用 · 本体 \(fmt(body)) · 用户数据 \(fmt(data)) · 总计 \(fmt(body + data))")
    semaphore.signal()
}

semaphore.wait()

func fmt(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
