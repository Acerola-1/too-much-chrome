# SwiftUI 实现对照表

本文档说明 `pages/index.html` 原型中每个设计元素与交互在原生 SwiftUI（macOS 14+）中的对应实现方式，
确保原型可以 1:1 落地为 SwiftUI 应用，不依赖 WebView。

> **正式实现已落地**：仓库根目录即 SwiftPM 工程（`swift run`）按本表完成原生实现，
> 扫描逻辑遵循 `detection-strategy.md`；`swift run tmc-scan` 可无头验证扫描结果。
> 原型与正式实现的差异（原型为 mock 数据 / 正式版为真实扫描）在实现中已按
> "加载动画绑定真实扫描进度"的原则处理。

## 数据模型

原型中 JS 的 `APPS` 数组对应 Swift 结构体：

```swift
enum AppType: String, CaseIterable {
    case electron, tauri, wails
}

enum VersionStatus {
    case current, ok, aging, outdated, unknown   // 对应绿/绿/黄/红/灰角标
}

struct DetectedApp: Identifiable {
    let id = UUID()
    let name: String
    let path: String            // .app 绝对路径
    let type: AppType
    let version: String?        // Electron 读框架 Info.plist，Tauri/Wails 可为空
    let status: VersionStatus
    let bodyBytes: Int64        // .app 本身体积
    let dataBytes: Int64        // ~/Library 下用户数据合计
    var totalBytes: Int64 { bodyBytes + dataBytes }
}
```

## 界面元素对照

| 原型元素（CSS/HTML） | SwiftUI 实现 | 说明 |
|---|---|---|
| `.app-window` 主窗口 | `WindowGroup` + `frame(minWidth: 1100, minHeight: 700)` | 固定最小尺寸 |
| `.toolbar` 毛玻璃工具栏 | macOS 26+ 用悬浮液态玻璃层：自定义 HStack + `.glassEffect(.regular, in: Rectangle())`，以 overlay 悬浮在网格区上方，滚动内容从玻璃下方穿过（玻璃需要背后有内容才有折射/透视质感，盖在不透明背景上会退化成普通材质）；低版本回退 `.background(.regularMaterial)` | 系统工具栏自带毛玻璃，但隐藏标题栏后需自绘 |
| `.traffic-lights` 红绿灯窗口按钮 | 原型中为装饰性元素（含玻璃光泽与悬停操控符号）；正式版 SwiftUI 用标准 `WindowGroup` 标题栏即自动获得红绿灯，无需自绘 | 若用 `.windowStyle(.hiddenTitleBar)` 才需自绘 HStack + Circle |
| `.filter-segment` 分段过滤器 | 胶囊形 `Button` 组（HStack）或 `Picker(.segmented)` | 原型为自定义胶囊样式，建议自绘 |
| `.replay-btn` 重播按钮 | `Button` + SF Symbol `arrow.triangle.2.circlepath` | hover 效果用 `.onHover` + scaleEffect |
| `.icon-grid` 图标网格 | `LazyVGrid(columns: Array(repeating: .init(.fixed(88)), count: 7))` | 7 列网格 |
| `.app-icon` 应用图标 | `NSWorkspace.shared.icon(forFile: path)` → `Image(nsImage:)` | 读取真实应用图标 |
| `.status-dot` 健康状态角标 | `overlay(alignment: .bottomTrailing)` + `Circle().fill(statusColor)` | 四档状态色 |
| `.stats-panel` 右侧报告面板 | HStack 右栏 + `.background(.regularMaterial)`，宽度动画用 `withAnimation` 修改 frame | 对应 0 → 368pt 展开 |
| `.stats-total` 大号数字滚动 | `Text("\(count)")` + `.contentTransition(.numericText())` | 数字翻滚动效 |
| `.stacked-bar` 本体/数据堆叠条 | 自定义 `GeometryReader` + `RoundedRectangle` 按占比分配宽度，或 Swift Charts 水平 `BarMark` 堆叠 | 宽度动画用 `.animation(.easeOut, value:)` |
| `.donut-svg` 环形占比图 | Swift Charts `SectorMark(angle:innerRadius:angularInset:)`（macOS 14+） | 中心数字用 `chartBackground` overlay |
| `.rank-row` 存储排行行 | `ForEach` 自定义行视图，双段条同 stacked-bar 实现 | 点击触发 `.popover` |
| `.app-popover` 详情弹层 | `.popover(isPresented:attachmentAnchor:)` + `.regularMaterial` | 箭头方向 `.leading`/`.trailing` |
| 暗色主题 | 语义色（`Color.primary` / `.secondary`）+ Asset Catalog 动态色 | 对应 `prefers-color-scheme` 覆盖 |
| `prefers-reduced-motion` 降级 | `@Environment(\.accessibilityReduceMotion)` | 所有动画分支判断 |

## 动画对照

| 原型动效 | SwiftUI 实现 | 说明 |
|---|---|---|
| 复印机扫描线开场（scanSweep + in-scan） | 光条 = `LinearGradient` 渐变尾 + 2pt 发光亮边（`shadow` 辉光），用 `withAnimation(.linear(duration: 1.1))` 从 -8% 位移到 104%；图标按列 `.blur(radius:)` 10→0 + opacity + scale(0.96→1)，`withAnimation(.easeOut(duration: 0.3))` | 已选定方案（2026-08-16，六概念对比后胜出）；参考实现 `LoadingConcepts/Concept6Scanline.swift`。原型中动画类在 `animationend` 摘除，避免 `fill: both` 压住 hover transform——SwiftUI 无此问题，动画结束值即终态 |
| 按列揭示时刻 | 列被扫中的时刻由该列中心 X 解析确定：`t = 60 + 1100 × colX / gridWidth × 0.96`，与光条线性位移严格换算对齐 | 列内图标按行序 45ms 逐个错开；SwiftUI 侧用 `Task.sleep` 编排，重播时用 run token/代际计数作废上一轮未完成调度 |
| 工具栏副标题随扫描滚动 | 扫描期间 `scanCount` 文案随图标显现逐个 +1、累加体积 | 原型为纯视觉润色；正式版应绑定真实扫描进度（`@Observable` ViewModel 的 `scannedCount`），让加载动画即进度反馈 |
| 条形/环形增长 | `.animation(.easeInOut(duration: 1), value: data)` | 过滤切换时自动重放 |
| 数字滚动 | `.contentTransition(.numericText(value:))` + `withAnimation` | 无需手写 rAF |
| 逐个入场延迟 | 按列揭示：`delay = 列扫中时刻 + 行序 × 45ms`，列扫中时刻由列中心 X 与光条线性位移换算 | 串行改为按列并行后总时长约 1.6s；正式版可绑定真实扫描进度 |

## 加载动画候选 · SwiftUI 参考实现

**已选定：⑥ 复印机扫描线**（2026-08-16 六概念对比后胜出），已落地 `pages/index.html` 开场动画；
其余五个概念保留在对比页 `pages/loading-concepts.html` 与 `LoadingConcepts/` 工程中备查。

六个开场动画概念均有可运行的 SwiftUI 原生实现，位于仓库根目录
`LoadingConcepts/`（SwiftPM 工程，macOS 14+，`swift run` 或 Xcode 打开 `Package.swift`，
`swift run --cycle` 自动巡览）。各概念实现按下表索引：

| 概念 | SwiftUI 技术 | 参考文件 |
|---|---|---|
| ① 标签页瀑布 | `matchedGeometryEffect` 标签↔图标共享几何变形 | `Concept1Tabs.swift` |
| ② 雷达扫描 | `AngularGradient` 光束 + `rotationEffect`，按槽位角度解析揭示时刻 | `Concept2Radar.swift` |
| ③ 有丝分裂 | 代际 spring 分裂 + `offset` 驱动黄金角螺旋簇 | `Concept3Mitosis.swift` |
| ④ 数据弹射 | `KeyframeAnimator` + `KeyframeTrack` 多轨（位移∝体积） | `Concept4Launch.swift` |
| ⑤ 群鸟降落 | `TimelineView(.animation)` 逐帧 Boids 模拟 | `Concept5Boids.swift` |
| ⑥ 复印机扫描线 | 线性光条 + 按列 `blur` 去模糊 | `Concept6Scanline.swift` |

网格在参考实现中采用固定单元格尺寸（`GridGeom`），槽位坐标可解析计算，
簇位置 / 弹射峰值 / 雷达角度均不依赖布局测量；正式版若改为响应式网格，
需用 `GeometryReader` 回填槽位坐标。

## 扫描与统计逻辑对照

| 原型行为 | SwiftUI 应用实现 |
|---|---|
| JS mock 数据聚合 | `@Observable final class ScanViewModel`，扫描结果存 `[DetectedApp]` |
| 应用枚举 | 遍历 `/Applications`、`~/Applications`（见 detection-strategy.md 扫描路径），`FileManager` 过滤 `.app` bundle |
| 框架检测 | 检查 `Contents/Frameworks/` 下 `Electron Framework.framework` 等（见 detection-strategy.md Tier 1-4） |
| 本体大小 | `FileManager` 递归累加 `.app` 目录 `totalFileAllocatedSize`（resourceValues） |
| 用户数据大小 | 按 bundle id / 应用名匹配 `~/Library/Application Support`、`~/Library/Caches`、`~/Library/Containers` 下目录，递归累加 |
| 后台扫描 | `Task.detached` / `actor`，主线程通过 `@MainActor` 更新 UI；扫描进度可用 `ProgressView` |
| 过滤联动重算 | ViewModel 暴露 `filteredApps` / `stats` 计算属性，视图自动刷新 |
| 单一类型过滤时隐藏类型分布区块 | 过滤到具体类型时“类型分布”无意义（必为 100% 单色环），用 `if filter == .all` 条件渲染该区块及其上方分割线 |

## 原型中不建议照搬的部分

| 原型做法 | 原因 | SwiftUI 替代 |
|---|---|---|
| `backdrop-filter` 多层叠加 | SwiftUI 无 CSS filter，多层 Material 有性能成本 | 每个毛玻璃区域用一层 Material 即可 |
| 绝对定位 popover + 手动翻转计算 | SwiftUI `.popover` 自带锚点与翻转 | 直接用 `.popover(attachmentAnchor:)` |
| `setTimeout` 编排动画序列 | 难以维护且不可中断 | `KeyframeAnimator` / `PhaseAnimator` 声明式编排 |
| 首字母渐变图标 | 原型无真实图标的占位方案 | 正式版直接用 `NSWorkspace.icon(forFile:)` |
