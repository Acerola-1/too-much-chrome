import Foundation

struct ConceptInfo: Identifiable {
    let id: Int
    let label: String
    let tagline: String
    let points: [String]
    let meta: [String]

    static let tabs = ConceptInfo(
        id: 0,
        label: "① 标签页瀑布",
        tagline: "每个 Electron 应用，都只是一枚获得自主意识的 Chrome 标签",
        points: [
            "名字双关的兑现时刻：标签条被挤爆，标签跌落、变形为应用图标落入网格",
            "本实现即 SwiftUI 杀手锏 matchedGeometryEffect：标签与图标共享几何，状态一翻即变形",
            "风险：Chrome 视觉语言需要克制处理——只保留标签剪影，配色融入系统主题"
        ],
        meta: ["时长 ≈ 2.2s", "移植成本 中", "新奇度 ★★★★★"]
    )

    static let radar = ConceptInfo(
        id: 1,
        label: "② 雷达扫描",
        tagline: "应用本质是检测器——扫描即加载，涟漪半径即体积",
        points: [
            "光束按角度扫过槽位、原地 ping 出图标：从结构上根治「中心堆叠」的视觉混乱",
            "信息编码：涟漪半径与应用体积成正比，Docker 的回波明显重于 Espanso",
            "将来可绑定真实扫描进度；SwiftUI 用 AngularGradient + rotationEffect 实现，移植成本最低"
        ],
        meta: ["时长 ≈ 1.9s", "移植成本 低", "新奇度 ★★★★"]
    )

    static let mitosis = ConceptInfo(
        id: 2,
        label: "③ 有丝分裂",
        tagline: "动画即论点：1 → 2 → 4 → 8 → … → 28，你在硬盘里养了 28 份同一引擎",
        points: [
            "Chromium 原子徽标先落场，指数分裂节奏越来越快，五代表后挤成一团，再散开归位",
            "指数增长的加速节奏天然把总时长压在 2 秒左右，没有冗长感",
            "SwiftUI 用 offset/scale 的 spring 编排代际节拍；风险：节拍不干脆会糊成一锅粥"
        ],
        meta: ["时长 ≈ 2.0s", "移植成本 中", "新奇度 ★★★★★"]
    )

    static let launch = ConceptInfo(
        id: 3,
        label: "④ 数据弹射",
        tagline: "动画即信息：飞行距离 ∝ 存储体积，飞得越远，占得越多",
        points: [
            "所有图标从中心一点爆发射出，Docker Desktop 冲得最远，落点带深度压缩与冲击涟漪",
            "体积最大的先发射、砸得最重——加载过程同时在预告排行榜",
            "本实现即 KeyframeAnimator + KeyframeTrack：位移/缩放/透明度多轨并行，SwiftUI 原生表达"
        ],
        meta: ["时长 ≈ 1.8s", "移植成本 中", "新奇度 ★★★★"]
    )

    static let boids = ConceptInfo(
        id: 4,
        label: "⑤ 群鸟降落",
        tagline: "35 只图标鸟先绕中心形成活的漩涡，再逐个脱离集群归位",
        points: [
            "Boids 群体智能（聚集 / 分离 / 对齐 + 漩涡切向力）：最「活」、wow 系数最高",
            "归位按槽位离中心的距离分层激活，落位像涟漪一样从中心扩散",
            "SwiftUI 用 TimelineView 逐帧驱动模拟；正式版如需此效果建议收敛参数并做降级"
        ],
        meta: ["时长 ≈ 2.6s", "移植成本 高", "新奇度 ★★★★★"]
    )

    static let scanline = ConceptInfo(
        id: 5,
        label: "⑥ 复印机扫描线",
        tagline: "诚实、冷静、绝对稳的兜底方案——光条扫过，图标逐列去模糊显现",
        points: [
            "复印机式进度感：扫到哪一列、哪一列亮起，节奏与「扫描磁盘」的叙事完全一致",
            "实现最简单、最不容易出 bug，适合作为正式版的保守选项",
            "新奇度为零——列在这里是为了给对比一个「克制」的锚点"
        ],
        meta: ["时长 ≈ 1.4s", "移植成本 低", "新奇度 ★★"]
    )

    static let all: [ConceptInfo] = [tabs, radar, mitosis, launch, boids, scanline]
}
