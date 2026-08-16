import Foundation
import Observation
import AppKit
import TooMuchChromeCore

/// 扫描状态与 UI 数据源。扫描在后台线程逐个应用进行，
/// 主线程随发现追加 apps——开场"扫描线"动画即真实扫描进度。
@MainActor
@Observable
final class ScanViewModel {

    enum Phase: Equatable {
        case idle
        case scanning(found: Int, seen: Int)
        case done
    }

    private(set) var phase: Phase = .idle
    private(set) var apps: [DetectedApp] = []

    /// nil = 全部
    var filter: AppType?
    /// 排行行 ↔ 网格图标 联动高亮
    var linkedID: UUID?

    private(set) var totalCandidates = 0
    private(set) var seenCandidates = 0

    private var icons: [UUID: NSImage] = [:]

    // MARK: 派生状态

    var isScanning: Bool {
        if case .scanning = phase { return true }
        return phase == .idle
    }

    var hasResults: Bool { !apps.isEmpty }

    var progress: Double {
        totalCandidates > 0 ? Double(seenCandidates) / Double(totalCandidates) : 0
    }

    var subtitle: String {
        switch phase {
        case .idle:
            return "尚未扫描"
        case .scanning(let found, _):
            return "正在扫描… 已发现 \(found) 个 WebView 应用"
        case .done:
            guard !apps.isEmpty else { return "未发现基于 WebView 的应用 🎉" }
            return "已扫描 \(apps.count) 个应用 · \(fmtBytes(totalBytes))"
        }
    }

    var filteredApps: [DetectedApp] {
        guard let filter else { return apps }
        return apps.filter { $0.type == filter }
    }

    var totalBytes: Int64 {
        filteredApps.reduce(0) { $0 + $1.totalBytes }
    }

    var bodyBytes: Int64 {
        filteredApps.reduce(0) { $0 + $1.bodyBytes }
    }

    var dataBytes: Int64 {
        filteredApps.reduce(0) { $0 + $1.dataBytes }
    }

    struct TypeCount: Identifiable {
        let type: AppType
        let count: Int
        var id: String { type.rawValue }
    }

    var typeCounts: [TypeCount] {
        let counts = Dictionary(grouping: filteredApps, by: \.type)
            .mapValues(\.count)
        return AppType.allCases
            .compactMap { type in counts[type].map { TypeCount(type: type, count: $0) } }
    }

    var top5: [DetectedApp] {
        filteredApps.sorted { $0.totalBytes > $1.totalBytes }.prefix(5).map { $0 }
    }

    var healthCounts: [(status: VersionStatus, count: Int)] {
        VersionStatus.allCases.compactMap { status in
            let n = filteredApps.filter { $0.status == status }.count
            return n > 0 ? (status, n) : nil
        }
    }

    // MARK: 扫描

    func scan() async {
        apps.removeAll()
        icons.removeAll()
        linkedID = nil
        seenCandidates = 0
        totalCandidates = 0
        phase = .scanning(found: 0, seen: 0)

        let urls = await Task.detached(priority: .userInitiated, operation: {
            AppScanner.candidateURLs()
        }).value
        totalCandidates = urls.count

        for url in urls {
            let detected = await Task.detached(priority: .utility, operation: {
                AppScanner.detect(at: url)
            }).value
            if let app = detected {
                icons[app.id] = NSWorkspace.shared.icon(forFile: url.path)
                apps.append(app)
                phase = .scanning(found: apps.count, seen: seenCandidates)
            }
            seenCandidates += 1
        }
        phase = .done
    }

    func rescan() async {
        await scan()
    }

    func icon(for app: DetectedApp) -> NSImage {
        icons[app.id] ?? NSWorkspace.shared.icon(forFile: app.path)
    }

    // MARK: 联动

    func setLinked(_ id: UUID?) {
        linkedID = id
    }
}

func fmtBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
