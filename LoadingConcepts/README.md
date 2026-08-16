# LoadingConcepts — SwiftUI 加载动画六概念对比台

`too-much-chrome.design/pages/loading-concepts.html` 的 SwiftUI 原生对应实现，
在同一个 macOS 窗口里完整运行六个开场动画概念，供选型对比。

## 运行

```bash
swift run
```

或用 Xcode 打开 `Package.swift` 后直接 Run。要求 **macOS 14+**（使用了
KeyframeAnimator / matchedGeometryEffect 变形 / contentTransition(.numericText) 等 API）。

## 操作

- 顶部胶囊（或数字键 `1`–`6`）切换概念
- `R` 或右上角按钮重播当前概念
- `swift run --cycle`：每 5 秒自动巡览下一个概念
- 系统开启「减少动态效果」时所有概念自动降级为直接显现

## 六个概念与 SwiftUI 技术要点

| 概念 | SwiftUI 实现 |
|---|---|
| ① 标签页瀑布 | `matchedGeometryEffect`：标签与图标共享几何 id，状态翻转即变形 |
| ② 雷达扫描 | `AngularGradient` 锥形光束 + `rotationEffect` 线性旋转，揭示时刻按槽位角度解析计算 |
| ③ 有丝分裂 | 原子徽标（轨道电子 `repeatForever`）+ 代际 spring 分裂，offset 驱动簇位置 |
| ④ 数据弹射 | `KeyframeAnimator` + `KeyframeTrack`：位移/缩放/透明度多轨并行，飞行距离 ∝ 体积 |
| ⑤ 群鸟降落 | `TimelineView(.animation)` 逐帧驱动 Boids 模拟（聚集/分离/对齐 + 漩涡） |
| ⑥ 复印机扫描线 | 线性位移光条 + 按列 `blur` 去模糊显现 |

网格采用固定单元格尺寸（`GridGeom`），槽位坐标可脱离布局解析计算，
各概念的簇位置 / 弹射峰值 / 雷达角度因此获得精确几何。
