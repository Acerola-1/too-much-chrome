// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TooMuchChrome",
    platforms: [.macOS(.v14)],
    targets: [
        // 扫描核心：应用枚举、类型检测、体积统计（无 UI 依赖）
        .target(
            name: "TooMuchChromeCore",
            path: "Sources/TooMuchChromeCore"
        ),
        // GUI 主程序
        .executableTarget(
            name: "TooMuchChrome",
            dependencies: ["TooMuchChromeCore"],
            path: "Sources/TooMuchChrome"
        ),
        // 无头扫描 CLI（验证扫描结果用）
        .executableTarget(
            name: "tmc-scan",
            dependencies: ["TooMuchChromeCore"],
            path: "Sources/tmc-scan"
        )
    ]
)
