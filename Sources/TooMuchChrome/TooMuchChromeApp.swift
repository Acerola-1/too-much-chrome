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
        // 隐藏原生标题栏（避免与自定义工具栏标题重复），
        // 红绿灯保留在左上角，由工具栏的 leading 留白让位——对齐原型布局
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
