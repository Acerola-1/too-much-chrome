import AppKit
import Combine
import Foundation
import Sparkle

/// Sparkle 自动更新（启动即后台定时检查，默认 24h；菜单栏手动触发）。
/// 由 App 持有以保持 updaterController 存活（Sparkle 要求）。
@MainActor
final class UpdateService: NSObject, ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    override init() {
        super.init()
        // 与 Sparkle 的 canCheckForUpdates 同步，供菜单项禁用状态使用
        updaterController.updater
            .publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// 手动检查更新（有新版本时 Sparkle 弹出更新窗口）
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
