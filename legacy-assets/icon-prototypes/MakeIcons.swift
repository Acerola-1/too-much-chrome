// Too Much Chrome — 应用图标绘制（CoreGraphics）
// 最终产物：仓库根 AppIcon.icon（macOS 26 分层 bundle，Icon Composer 可直接打开）
// 过程产物（分层源/配色候选/预览）归档在 legacy-assets/icon-prototypes/
// 用法：swift legacy-assets/icon-prototypes/MakeIcons.swift（在仓库根执行）
// 注：历史概念 A-D 与 E-brand-lens 旧产物均在 legacy-assets/，更早的代码可从 git 历史找回。

import AppKit
import CoreGraphics

// MARK: - 基础设施

let S: CGFloat = 1024
let outRoot = URL(fileURLWithPath: "legacy-assets/icon-prototypes")

func makeContext(_ size: CGFloat) -> CGContext {
    guard let ctx = CGContext(
        data: nil, width: Int(size), height: Int(size),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("context 创建失败") }
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    return ctx
}

func savePNG(_ ctx: CGContext, _ url: URL) {
    let dir = url.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    guard let img = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
    else { fatalError("PNG 写入失败: \(url.path)") }
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    // 必须用 srgbRed：CGColor(red:) 产生 Generic RGB，
    // 与 CGGradient 的 sRGB 色彩空间不兼容会返回 nil
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

func gradient(_ hexes: [UInt32], _ alphas: [CGFloat] = []) -> CGGradient {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    // 单色 + locations 为 nil 时 CGGradient 返回 nil，复制一份并展开透明度
    var hs = hexes
    var asx = alphas
    if hs.count == 1 {
        hs = [hs[0], hs[0]]
        asx = [asx.first ?? 1, asx.count > 1 ? asx[1] : 1]
    }
    let colors = hs.enumerated().map { i, h in
        color(h, i < asx.count ? asx[i] : 1)
    } as CFArray
    return CGGradient(colorsSpace: cs, colors: colors, locations: nil)!
}

/// 超级椭圆（Apple squircle 近似，n≈4.8）
func squircle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, n: CGFloat = 4.8) -> CGPath {
    let path = CGMutablePath()
    let steps = 360
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + r * (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / n)
        let y = cy + r * (st < 0 ? -1 : 1) * pow(abs(st), 2 / n)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

// MARK: - 概念 E：放大镜 + 四方格品牌图标
// 镜内 2×2 整齐排列 Chrome / Electron / Tauri / VS Code（经典三框架 + 最常见 Electron 应用），
// 一条细扫描线沿行间隙横贯（产品签名）。镜外为干净的底色渐变。
// 注：四格均为官方图标原样引用（official/，来源见 README），缺图时才回退手绘近似。

/// 品牌贴片：优先绘制官方图标（legacy-assets/icon-prototypes/official/，来源见 README），
/// 缺失时回退手绘近似。dark 变体仅作用于手绘贴片底色与官方图标投影。
enum Brand { case chrome, electron, tauri, vscode }

private var officialCache: [String: CGImage?] = [:]

func loadOfficial(_ name: String) -> CGImage? {
    if let cached = officialCache[name] { return cached }
    let url = URL(fileURLWithPath: "legacy-assets/icon-prototypes/official/\(name)")
    let img = CGImageSourceCreateWithURL(url as CFURL, nil)
        .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    officialCache[name] = img
    return img
}

/// 裁掉图片四周的透明留白（icns 提取版自带大片 padding，是四贴片视觉
/// 大小不一的根因）；返回按 alpha 内容 bbox 裁剪后的图
func trimAlpha(_ img: CGImage) -> CGImage {
    let w = img.width, h = img.height
    guard w > 0, h > 0,
          let ctx = CGContext(
              data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return img }
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let data = ctx.data else { return img }
    let buf = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h {
        for x in 0..<w {
            if buf[(y * w + x) * 4 + 3] > 8 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
    }
    guard maxX > minX, maxY > minY else { return img }
    // bitmap 内存 y=0 为顶行，CGImage 坐标 y 向上，需翻转
    let rect = CGRect(x: minX, y: h - 1 - maxY, width: maxX - minX + 1, height: maxY - minY + 1)
    return img.cropping(to: rect) ?? img
}

func brandTile(_ ctx: CGContext, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat, _ kind: Brand, dark: Bool = false) {
    let plate: UInt32 = dark ? 0xe4e7ec : 0xf4f6f9   // 手绘贴片底色
    let ring: UInt32 = dark ? 0xe4e7ec : 0xf4f6f9    // Chrome 手绘中心环同底色
    let rect = CGRect(x: x, y: y, width: s, height: s)
    let path = CGPath(roundedRect: rect, cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: color(0x000000, dark ? 0.45 : 0.30))
    ctx.addPath(path)
    ctx.clip()

    let officialName: String?
    switch kind {
    case .chrome: officialName = "chrome.png"
    case .electron: officialName = "electron.png"
    case .tauri: officialName = "tauri.png"
    case .vscode: officialName = "vscode.png"
    }
    if let img = officialName.flatMap(loadOfficial).map(trimAlpha) {
        // 官方图标原样直绘（不加白底贴片/统一 inset）：按内容 bbox
        // aspect-fit 到格内，圆形 logo 自然露出底色
        let box = s * 0.94
        let scale = min(box / CGFloat(img.width), box / CGFloat(img.height))
        let w = CGFloat(img.width) * scale, h = CGFloat(img.height) * scale
        ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: color(0x000000, dark ? 0.5 : 0.22))
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: x + (s - w) / 2, y: y + (s - h) / 2, width: w, height: h))
        ctx.restoreGState()
        return
    }

    // ---- 手绘回退 ----
    let bg: UInt32 = kind == .vscode ? 0x007ACC : plate
    ctx.drawLinearGradient(
        gradient([0xffffff, bg]),
        start: CGPoint(x: x, y: y + s), end: CGPoint(x: x, y: y), options: []
    )
    let cx = x + s / 2, cy = y + s / 2

    switch kind {
    case .chrome:
        // 三色扇区（红上/黄左下/绿右下，留白隙）+ 中心白环蓝圆
        let R = s * 0.36
        let segs: [(UInt32, CGFloat, CGFloat)] = [
            (0xEA4335, 30, 150),   // 红：上半
            (0xFBBC05, 150, 270),  // 黄：左下
            (0x34A853, 270, 390)   // 绿：右下
        ]
        for (hex, a0, a1) in segs {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: cx, y: cy))
            p.addArc(center: CGPoint(x: cx, y: cy), radius: R,
                     startAngle: (a0 + 2) * .pi / 180, endAngle: (a1 - 2) * .pi / 180, clockwise: false)
            p.closeSubpath()
            ctx.addPath(p)
            ctx.setFillColor(color(hex))
            ctx.fillPath()
        }
        ctx.setFillColor(color(ring))
        ctx.fillEllipse(in: CGRect(x: cx - R * 0.62, y: cy - R * 0.62, width: R * 1.24, height: R * 1.24))
        ctx.setFillColor(color(0x4285F4))
        ctx.fillEllipse(in: CGRect(x: cx - R * 0.54, y: cy - R * 0.54, width: R * 1.08, height: R * 1.08))

    case .electron:
        // 三条倾斜轨道 + 中心圆点（Electron 原子，青灰官方色）
        ctx.setStrokeColor(color(0x9FB6BD, 0.95))
        ctx.setLineWidth(s * 0.045)
        for i in 0..<3 {
            ctx.saveGState()
            ctx.translateBy(x: cx, y: cy)
            ctx.rotate(by: CGFloat(i) * .pi / 3)
            ctx.strokeEllipse(in: CGRect(x: -s * 0.36, y: -s * 0.13, width: s * 0.72, height: s * 0.26))
            let theta = CGFloat(i) * 2.1 + 0.8
            let ex = s * 0.36 * cos(theta) * 0.9
            let ey = s * 0.13 * sin(theta)
            ctx.setFillColor(color(0x47848F))
            ctx.fillEllipse(in: CGRect(x: ex - s * 0.045, y: ey - s * 0.045, width: s * 0.09, height: s * 0.09))
            ctx.restoreGState()
        }
        ctx.setFillColor(color(0x9FB6BD))
        ctx.fillEllipse(in: CGRect(x: cx - s * 0.07, y: cy - s * 0.07, width: s * 0.14, height: s * 0.14))

    case .tauri:
        // 黄→青渐变圆环 + 偏心内点（Tauri 双色语言）
        let R = s * 0.30
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: cx - R, y: cy - R, width: R * 2, height: R * 2))
        ctx.clip()
        ctx.drawLinearGradient(
            gradient([0xFFC131, 0x24C8D8]),
            start: CGPoint(x: cx - R, y: cy + R), end: CGPoint(x: cx + R, y: cy - R), options: []
        )
        ctx.restoreGState()
        ctx.setFillColor(color(ring))
        ctx.fillEllipse(in: CGRect(x: cx - R * 0.62, y: cy - R * 0.62, width: R * 1.24, height: R * 1.24))
        ctx.setFillColor(color(0x24C8D8))
        ctx.fillEllipse(in: CGRect(x: cx - R * 0.30, y: cy + R * 0.02, width: R * 0.60, height: R * 0.60))

    case .vscode:
        // 蓝底 + 白色双角括号（VS Code 的 <> 语言）
        ctx.setStrokeColor(color(0xffffff))
        ctx.setLineWidth(s * 0.075)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let m = s * 0.22
        ctx.move(to: CGPoint(x: cx - m * 0.35, y: cy))
        ctx.addLine(to: CGPoint(x: cx - m, y: cy - m * 0.8))
        ctx.strokePath()
        ctx.move(to: CGPoint(x: cx - m * 0.35, y: cy))
        ctx.addLine(to: CGPoint(x: cx - m, y: cy + m * 0.8))
        ctx.strokePath()
        ctx.move(to: CGPoint(x: cx + m * 0.35, y: cy))
        ctx.addLine(to: CGPoint(x: cx + m, y: cy - m * 0.8))
        ctx.strokePath()
        ctx.move(to: CGPoint(x: cx + m * 0.35, y: cy))
        ctx.addLine(to: CGPoint(x: cx + m, y: cy + m * 0.8))
        ctx.strokePath()
    }
    ctx.restoreGState()
}

// MARK: - 概念 E：放大镜 + 四方格品牌图标（macOS 26 分层版）
// 按苹果新图标标准拆层（Icon Composer 工作流）：
//   Background 层 = 满幅底渐变 + 2×2 品牌网格 + 细扫描线（配色可换，见 paletteCandidates）
//   Front 层     = 放大镜（透明底，系统施加 Liquid Glass 光学与倾斜视差，
//                  "放大镜浮在网格上检视"——玻璃近白元素满足前景规范）
// 布局：镜心 (452, 578)，半径 264。

let eLensCenter = CGPoint(x: 452, y: 578)
let eLensRadius: CGFloat = 264
let eRingWidth: CGFloat = 42

/// Background 层配色盘：底渐变（top→bottom）+ 镜心晕光 + 扫描线双色
struct BgPalette {
    let name: String        // 导出文件名后缀
    let label: String       // 中文说明
    let top: UInt32, bottom: UInt32
    let glow: UInt32, glowAlpha: CGFloat
    let scanGlow: UInt32, scanGlowAlpha: CGFloat
    let scanCore: UInt32, scanCoreAlpha: CGFloat
}

/// 当前默认（碳黑，用户选定）：近纯黑 + 冷蓝晕光，最克制高级
let paletteDefaultDark = BgPalette(
    name: "carbon", label: "碳黑（当前默认）",
    top: 0x14141c, bottom: 0x000000,
    glow: 0x1d4ed8, glowAlpha: 0.30,
    scanGlow: 0x60a5fa, scanGlowAlpha: 0.30,
    scanCore: 0xbfe0ff, scanCoreAlpha: 0.95
)

/// 浅色备选（提饱和，去掉旧版中心白光晕——泛白感根源）
let paletteLight = BgPalette(
    name: "light", label: "提饱和浅青→蓝（备选）",
    top: 0x86e4dc, bottom: 0x0a5fd0,
    glow: 0, glowAlpha: 0,
    scanGlow: 0x6fd8ff, scanGlowAlpha: 0.30,
    scanCore: 0x0a63e8, scanCoreAlpha: 0.8
)

/// 候选配色（历史备选存档；改默认 = 把中意的一套参数拷给 paletteDefaultDark）：
/// 选色原则——底色不与四枚 logo 的主色（红/黄/绿/蓝/青）正面撞色，
/// 晕光低透明度托底不泛白。
let paletteCandidates: [BgPalette] = [
    BgPalette(   // 深靛青：曾经的默认
        name: "indigo", label: "深靛青（前默认）",
        top: 0x1c3060, bottom: 0x070b1c,
        glow: 0x2e6bd6, glowAlpha: 0.42,
        scanGlow: 0x6fd8ff, scanGlowAlpha: 0.34,
        scanCore: 0xa5e6ff, scanCoreAlpha: 0.95
    ),
    BgPalette(   // 深紫：logo 全系无紫色，对比最干净
        name: "abyss-purple", label: "深空紫",
        top: 0x33206e, bottom: 0x0c0620,
        glow: 0x8b5cf6, glowAlpha: 0.34,
        scanGlow: 0xc4b5fd, scanGlowAlpha: 0.30,
        scanCore: 0xe4dcff, scanCoreAlpha: 0.95
    ),
    BgPalette(   // 深青：呼应 Tauri/Electron 的青，整体同色系
        name: "abyss-teal", label: "深海青",
        top: 0x0c4a4e, bottom: 0x02181c,
        glow: 0x06b6d4, glowAlpha: 0.30,
        scanGlow: 0x67e8f9, scanGlowAlpha: 0.28,
        scanCore: 0xcffcff, scanCoreAlpha: 0.95
    ),
    BgPalette(   // 酒红：暖色反差，四枚冷色 logo 被衬得最亮
        name: "burgundy", label: "酒红",
        top: 0x4a1030, bottom: 0x14040e,
        glow: 0xd9326e, glowAlpha: 0.28,
        scanGlow: 0xfb7185, scanGlowAlpha: 0.28,
        scanCore: 0xffd3dd, scanCoreAlpha: 0.95
    ),
    BgPalette(   // 石墨：中性蓝灰，不抢戏，纯工具感
        name: "graphite", label: "石墨蓝灰",
        top: 0x2f3542, bottom: 0x0d0f14,
        glow: 0x5ac8fa, glowAlpha: 0.24,
        scanGlow: 0x5ac8fa, scanGlowAlpha: 0.28,
        scanCore: 0xd6f2ff, scanCoreAlpha: 0.95
    )
]

/// Background 层（画满整幅；squircle 裁剪与光照由系统处理）
func drawEBackground(_ ctx: CGContext, _ p: BgPalette) {
    ctx.drawLinearGradient(
        gradient([p.top, p.bottom]),
        start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: []
    )
    if p.glowAlpha > 0 {
        // 网格后方晕光，托出四枚 logo（低透明度，不泛白）
        ctx.drawRadialGradient(
            gradient([p.glow], [p.glowAlpha, 0]),
            startCenter: CGPoint(x: eLensCenter.x, y: eLensCenter.y), startRadius: 0,
            endCenter: CGPoint(x: eLensCenter.x, y: eLensCenter.y), endRadius: S * 0.52, options: []
        )
    }
    ctx.translateBy(x: eLensCenter.x, y: eLensCenter.y)
    let tile: CGFloat = 166, gap: CGFloat = 26
    let grid: [(Int, Int, Brand)] = [
        (0, 1, .chrome),    // 左上
        (1, 1, .electron),  // 右上
        (0, 0, .tauri),     // 左下
        (1, 0, .vscode)     // 右下
    ]
    for (col, row, kind) in grid {
        let x = -tile - gap / 2 + CGFloat(col) * (tile + gap)
        let y = -tile - gap / 2 + CGFloat(row) * (tile + gap)
        brandTile(ctx, x, y, tile, kind, dark: true)
    }
    // 细扫描线沿行间隙横贯
    let lineY: CGFloat = -gap / 2
    ctx.setStrokeColor(color(p.scanGlow, p.scanGlowAlpha))
    ctx.setLineWidth(14)
    ctx.move(to: CGPoint(x: -eLensRadius, y: lineY))
    ctx.addLine(to: CGPoint(x: eLensRadius, y: lineY))
    ctx.strokePath()
    ctx.setStrokeColor(color(p.scanCore, p.scanCoreAlpha))
    ctx.setLineWidth(5)
    ctx.move(to: CGPoint(x: -eLensRadius, y: lineY))
    ctx.addLine(to: CGPoint(x: eLensRadius, y: lineY))
    ctx.strokePath()
}

/// Front 层：放大镜（透明底）——精工银框 + 手柄，金属质感程序化绘制；
/// 镜片完全透出下层内容，玻璃折射/高光交给系统 Liquid Glass
func drawEFront(_ ctx: CGContext) {
    let cx = eLensCenter.x, cy = eLensCenter.y, r = eLensRadius
    let ring = eRingWidth
    let rOut = r + ring / 2, rIn = r - ring / 2

    ctx.saveGState()
    ctx.translateBy(x: cx, y: cy)

    // 手柄（先画，被镜框金属接缝压在下面）：右下 45°，圆柱倒角渐变 + 中线高光
    ctx.saveGState()
    ctx.rotate(by: -.pi / 4)
    let handle = CGRect(x: rOut - 18, y: -28, width: 238, height: 56)
    ctx.setShadow(offset: CGSize(width: 0, height: -9), blur: 24, color: color(0x000000, 0.26))
    ctx.addPath(CGPath(roundedRect: handle, cornerWidth: 28, cornerHeight: 28, transform: nil))
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([0xf7fafc, 0xa7b3c1, 0x76838f, 0xd9e1e9]),
        start: CGPoint(x: 0, y: 28), end: CGPoint(x: 0, y: -28), options: []
    )
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.setStrokeColor(color(0xffffff, 0.42))
    ctx.setLineWidth(5)
    ctx.move(to: CGPoint(x: rOut + 12, y: 9))
    ctx.addLine(to: CGPoint(x: handle.maxX - 24, y: 9))
    ctx.strokePath()
    // 末端收束箍
    ctx.setStrokeColor(color(0x5c6a76, 0.35))
    ctx.setLineWidth(3)
    ctx.move(to: CGPoint(x: handle.maxX - 34, y: -28))
    ctx.addLine(to: CGPoint(x: handle.maxX - 34, y: 28))
    ctx.strokePath()
    ctx.restoreGState()

    // 镜框整体落影（环 + 手柄一次成型感）
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: color(0x000000, 0.28))
    ctx.setFillColor(color(0x9aa7b8))
    ctx.addEllipse(in: CGRect(x: -rOut, y: -rOut, width: rOut * 2, height: rOut * 2))
    ctx.addEllipse(in: CGRect(x: -rIn, y: -rIn, width: rIn * 2, height: rIn * 2))
    ctx.fillPath(using: .evenOdd)
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // 银色环体：左上主光 + 右下反射光的双向拉丝渐变
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: -rOut, y: -rOut, width: rOut * 2, height: rOut * 2))
    ctx.addEllipse(in: CGRect(x: -rIn, y: -rIn, width: rIn * 2, height: rIn * 2))
    ctx.clip(using: .evenOdd)
    ctx.drawLinearGradient(
        gradient([0xfbfcfe, 0xc3cdd8, 0x8794a3, 0xd5dde5, 0xf2f5f9]),
        start: CGPoint(x: -rOut, y: rOut), end: CGPoint(x: rOut, y: -rOut), options: []
    )
    ctx.restoreGState()

    // 外缘亮边 + 内缘暗唇（倒角）
    ctx.setStrokeColor(color(0xffffff, 0.65))
    ctx.setLineWidth(2)
    ctx.strokeEllipse(in: CGRect(x: -rOut + 1, y: -rOut + 1, width: (rOut - 1) * 2, height: (rOut - 1) * 2))
    ctx.setStrokeColor(color(0x5c6a76, 0.45))
    ctx.setLineWidth(2)
    ctx.strokeEllipse(in: CGRect(x: -rIn + 1, y: -rIn + 1, width: (rIn - 1) * 2, height: (rIn - 1) * 2))

    // 贴框内缘的细弧反光（镜头镀膜式，左上主高光 + 右下副弧，不压镜内图标）
    ctx.setStrokeColor(color(0xffffff, 0.6))
    ctx.setLineWidth(6)
    ctx.setLineCap(.round)
    ctx.addArc(center: .zero, radius: rIn - 9, startAngle: .pi * 0.62, endAngle: .pi * 0.92, clockwise: false)
    ctx.strokePath()
    ctx.setStrokeColor(color(0xffffff, 0.28))
    ctx.setLineWidth(5)
    ctx.addArc(center: .zero, radius: rIn - 9, startAngle: -.pi * 0.32, endAngle: -.pi * 0.10, clockwise: false)
    ctx.strokePath()

    // 手柄-镜框金属接缝环（盖住接合处）
    ctx.saveGState()
    ctx.rotate(by: -.pi / 4)
    let collar = CGRect(x: rOut - 24, y: -34, width: 26, height: 68)
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: color(0x000000, 0.30))
    ctx.addPath(CGPath(roundedRect: collar, cornerWidth: 10, cornerHeight: 10, transform: nil))
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([0xf1f4f8, 0x8e9bab, 0xcdd6df]),
        start: CGPoint(x: 0, y: 34), end: CGPoint(x: 0, y: -34), options: []
    )
    ctx.restoreGState()

    ctx.restoreGState()
}

/// 合成预览（旧格式 icns 用）：bg + front 叠加后裁 squircle
func conceptE(_ palette: BgPalette = paletteDefaultDark) -> CGContext {
    let bg = makeContext(S)
    drawEBackground(bg, palette)
    guard let bgImage = bg.makeImage() else { fatalError() }

    let ctx = makeContext(S)
    ctx.addPath(squircle(S / 2, S / 2, S * 0.402))
    ctx.clip()
    ctx.draw(bgImage, in: CGRect(x: 0, y: 0, width: S, height: S))
    drawEFront(ctx)
    return ctx
}

// MARK: - 导出（仓库根 AppIcon.icon 分层 bundle）

// 组装 Icon Composer 可直接打开的分层 .icon bundle（macOS 26 格式：
// icon.json + Assets/，与 hagimi-monitor 项目同构）。
// 深色优先：Background 只填默认槽（= 碳黑底），明暗外观下图标均为深色；
// 历史分层源/候选配色/预览见 legacy-assets/icon-prototypes/E-brand-lens/。
let iconBundle = URL(fileURLWithPath: "AppIcon.icon")
let iconAssets = iconBundle.appendingPathComponent("Assets")
let fm = FileManager.default
try? fm.createDirectory(at: iconAssets, withIntermediateDirectories: true)

// Background 层（默认外观 = paletteDefaultDark）
let bgDark = makeContext(S)
drawEBackground(bgDark, paletteDefaultDark)
savePNG(bgDark, iconAssets.appendingPathComponent("background-dark.png"))
// Front 层（放大镜，透明底）
let front = makeContext(S)
drawEFront(front)
savePNG(front, iconAssets.appendingPathComponent("front.png"))

let iconJSON = """
{
  "fill" : {
    "automatic-gradient" : "srgb:0.02700,0.04300,0.11000,1.00000"
  },
  "groups" : [
    {
      "layers" : [
        {
          "glass" : true,
          "hidden" : false,
          "image-name" : "front.png",
          "name" : "Lens",
          "position" : {
            "scale" : 1,
            "translation-in-points" : [
              0,
              0
            ]
          }
        },
        {
          "glass" : false,
          "hidden" : false,
          "image-name" : "background-dark.png",
          "name" : "Background",
          "position" : {
            "scale" : 1,
            "translation-in-points" : [
              0,
              0
            ]
          }
        }
      ],
      "shadow" : {
        "kind" : "neutral",
        "opacity" : 0.5
      },
      "translucency" : {
        "enabled" : true,
        "value" : 0.25
      }
    }
  ],
  "supported-platforms" : {
    "circles" : [
      "watchOS"
    ],
    "squares" : "shared"
  }
}
"""
try? iconJSON.write(to: iconBundle.appendingPathComponent("icon.json"),
                    atomically: true, encoding: .utf8)
print("✓ AppIcon.icon（仓库根，Icon Composer 分层 bundle，默认配色：\(paletteDefaultDark.label)）")
