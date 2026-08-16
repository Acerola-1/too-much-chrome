import SwiftUI

final class LabModel: ObservableObject {
    @Published var concept = 0
    @Published var run = 0

    /// `--cycle` 启动参数：每 5 秒自动切换到下一个概念（自动巡览）
    let autoCycle: Bool

    init() {
        autoCycle = CommandLine.arguments.contains("--cycle")
    }

    func select(_ index: Int) { concept = index }
    func replay() { run += 1 }
}

@main
struct LoadingConceptsApp: App {
    @StateObject private var model = LabModel()

    var body: some Scene {
        WindowGroup("加载动画 · 六概念对比台") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 940)
        }
        .commands {
            CommandMenu("概念") {
                ForEach(ConceptInfo.all) { info in
                    Button(info.label) { model.select(info.id) }
                        .keyboardShortcut(KeyEquivalent(Character("\(info.id + 1)")), modifiers: [])
                }
                Divider()
                Button("重播当前概念") { model.replay() }
                    .keyboardShortcut("r", modifiers: [])
            }
        }
    }
}
