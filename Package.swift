// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TooMuchChrome",
    platforms: [.macOS(.v14)],
    dependencies: [
        // 自动更新（二进制 target，发布流水线用其 bin/ 工具生成 appcast）
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0")
    ],
    targets: [
        // 扫描核心：应用枚举、类型检测、体积统计（无 UI 依赖）
        .target(
            name: "TooMuchChromeCore",
            path: "Sources/TooMuchChromeCore"
        ),
        // GUI 主程序
        .executableTarget(
            name: "TooMuchChrome",
            dependencies: ["TooMuchChromeCore", "Sparkle"],
            path: "Sources/TooMuchChrome"
        ),
        // 无头扫描 CLI（验证扫描结果用）
        .executableTarget(
            name: "tmc-scan",
            dependencies: ["TooMuchChromeCore"],
            path: "Sources/tmc-scan"
        ),
        // 核心逻辑单元测试（版本带判定等纯逻辑）
        .testTarget(
            name: "TooMuchChromeCoreTests",
            dependencies: ["TooMuchChromeCore"],
            path: "Tests/TooMuchChromeCoreTests"
        )
    ]
)
