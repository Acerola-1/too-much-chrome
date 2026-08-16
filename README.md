# Too Much Chrome — macOS 原生应用

扫描 macOS 上所有基于 Chromium / WebView 的应用，回答一个问题：
"我的电脑里到底藏了多少个 Chrome？"

`too-much-chrome.design/pages/index.html` 原型的 SwiftUI 原生实现，
扫描逻辑遵循仓库根目录 `detection-strategy.md`。

## 工程结构

SwiftPM 包（Xcode 可直接打开 `Package.swift` 开发），分发用脚本打包 .app：

```
Package.swift               # SwiftPM 清单（Core 库 + GUI + CLI + 测试）
Sources/TooMuchChromeCore/  # 扫描核心（无 UI 依赖）
Sources/TooMuchChrome/      # SwiftUI GUI
Sources/tmc-scan/           # 无头扫描 CLI
Tests/                      # 单元测试（swift test）
scripts/build-app.sh        # 打包 / 签名 / 公证 / DMG 流水线
launch.sh                   # 日常开发启动（内部走 scripts/build-app.sh dev）
```

## 运行

```bash
./launch.sh            # 一键启动：release 构建 + 自动打包 .app + 打开 GUI
./launch.sh cli        # 构建并运行无头扫描 CLI（tmc-scan）
swift test             # 单元测试
```

或手动：

```bash
swift run              # GUI 主程序
swift run tmc-scan     # 无头扫描 CLI（终端打印检测结果，用于验证）
```

或用 Xcode 打开 `Package.swift` 直接 Run。要求 **macOS 14+**；
在 macOS 26+ 上自动启用液态玻璃（`glassEffect`），低版本回退毛玻璃材质。

## 对外分发（Developer ID 签名 + Apple 公证）

机器上已有 `Developer ID Application: jiliang mo (VTQ6S5M4K3)` 证书，
公证流水线在 `scripts/build-app.sh`（身份/团队号/版本号在脚本顶部配置）：

```bash
./scripts/build-app.sh release   # 组装 .app + Developer ID 签名（硬运行时 + 时间戳）
./scripts/build-app.sh notarize  # 提交 Apple 公证并 staple 票据到 .app
./scripts/build-app.sh dmg       # 生成并公证 DMG（对外分发物）
```

首次公证前，一次性把凭证存进钥匙串（app 专用密码在
[appleid.apple.com](https://appleid.apple.com) → 登录与安全 → App 专用密码 生成）：

```bash
xcrun notarytool store-credentials tmc-notary \
  --apple-id "你的AppleID" --team-id "VTQ6S5M4K3" --password "app专用密码"
```

公证状态与历史可随时用 `xcrun notarytool history --keychain-profile tmc-notary` 查看。

## 功能

- **真实扫描**：`/Applications` 与 `~/Applications` 顶层 `.app`
  - Tier 1（高准确率）：Electron / CEF / NW.js——按 `Contents/Frameworks` 框架特征识别
  - Tier 2（实验性）：Tauri / Wails——Bundle ID / 资源目录关键词，兼容主二进制内构建路径特征兜底
  - Tier 3：完整浏览器（Chrome / Edge / Brave / Arc / Vivaldi / Opera 等）仅列出
- **体积统计**：`.app` 本体（递归分配大小）+ `~/Library` 用户数据
  （Application Support / Caches / Containers，按 bundle id 与应用名双匹配）
- **版本健康度**：按 detection-strategy.md 的 Electron / Chromium 版本带判定五档状态
- **开场动画**：选定的"复印机扫描线"绑定真实扫描进度——光条位置即扫描进度，
  图标按发现顺序去模糊显现
- **报告面板**：总数 / 存储占用（本体 vs 数据）/ 类型分布环形图 / Top 5 排行 / 健康度
- **详情弹层**：存储分解、安装路径、在 Finder 中显示
- 排行行 ↔ 网格图标联动高亮；`⌘R` 重新扫描；
  「减少动态效果」开启时跳过入场动画

## 仓库结构

```
├── Package.swift              # SwiftPM 工程（本仓库即主工程）
├── Sources/
│   ├── TooMuchChromeCore/     # 扫描核心（无 UI 依赖，可独立复用）
│   │   ├── Model.swift        # AppType / VersionStatus / DetectedApp / 版本带
│   │   └── AppScanner.swift   # 枚举、检测、体积统计
│   ├── TooMuchChrome/         # GUI（SwiftUI，macOS 14+）
│   └── tmc-scan/              # 无头扫描 CLI
├── detection-strategy.md      # 检测分层策略与版本带定义
├── too-much-chrome.design/    # HTML 原型、设计令牌与 SwiftUI 对照文档
└── LoadingConcepts/           # 开场动画六概念的独立演示工程
```

已知局限见 detection-strategy.md「已知局限」：Tauri/Wails 依赖开发者命名规范；
~/Library 数据目录按 bundle id / 名称匹配，个别应用使用自定义路径时会漏计。
