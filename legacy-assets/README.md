# legacy-assets — 历史资产归档

存放项目演进过程中**已被取代、不再使用的资产资料**。

- **不参与编译**：本目录不被 `Package.swift` 的任何 target 引用
  （SwiftPM 只编译 `Sources/` 与 `Tests/`），`scripts/build-app.sh`
  与 `.github/workflows/release.yml` 也均不读取这里的内容。
- **仅作存档**：如需追溯设计过程或复用旧素材，从这里翻找即可；
  对应的生成代码可从 git 历史找回。

## 内容清单

| 目录/文件 | 原位置 | 归档原因 |
|---|---|---|
| `icon-prototypes/` | 仓库根 `icon-prototypes/` | 图标工作坊整体归档：概念 E 全部产物（master/iconset/icns/分层源/候选配色/预览/`AppIcon.icon` 旧位置）、官方 logo 素材与 `MakeIcons.swift` 生成器。最终图标已定型为仓库根 `AppIcon.icon/`（碳黑配色）；重跑生成器：`swift legacy-assets/icon-prototypes/MakeIcons.swift` |
| `icon-concepts/A-scanline/` | `icon-prototypes/` | 图标概念 A（扫描发现），已选定概念 E |
| `icon-concepts/B-atom/` | `icon-prototypes/` | 图标概念 B（Chromium 原子），同上 |
| `icon-concepts/C-pile/` | `icon-prototypes/` | 图标概念 C（堆积超载），同上 |
| `icon-concepts/D-lens/` | `icon-prototypes/` | 图标概念 D（放大镜早期版），同上 |
| `icon-concepts/overview.png` | `icon-prototypes/` | 五概念对比拼图（含已归档概念，已过时） |
| `official-candidates/vscode-*` | `icon-prototypes/official/` | VS Code 图标候选（mac icns / win ico / 候选对比图），已定为官网 apple-touch-icon 版 |
| `too-much-chrome.design/` | 仓库根 `too-much-chrome.design/` | 上线前 UI 原型与设计对照文档整体归档：`pages/index.html`（扫描结果 UI 原型）、`pages/loading-concepts.html`（六动画概念对比）、`colors_and_type.css`（设计令牌）、`swiftui-mapping.md`（原型 ↔ SwiftUI 对照）、`design.design`（原型元数据）、两个验证 JSON 与 `.preflight/`。选定方案均已实装进 GUI |
| `LoadingConcepts/` | 仓库根 `LoadingConcepts/` | 开场动画六概念独立 SwiftPM 演示工程。选定的"扫描线"概念（⑥）已实装进 GUI（`Sources/TooMuchChrome/ContentView.swift` 的 `ScanlineOverlay`）；此归档用于追溯其余概念的完整源码 |
