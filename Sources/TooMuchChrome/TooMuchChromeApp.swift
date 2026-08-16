import SwiftUI

@main
struct TooMuchChromeApp: App {
    @State private var model = ScanViewModel()

    var body: some Scene {
        WindowGroup("Too Much Chrome") {
            ContentView()
                .environment(model)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .defaultSize(width: 1280, height: 800)
        // 隐藏系统标题栏：标题/过滤器/重扫同处一条自定义工具栏，红绿灯由其左侧留白让位
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("扫描") {
                Button("重新扫描") {
                    Task { await model.rescan() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.isScanning)
            }
        }
    }
}
