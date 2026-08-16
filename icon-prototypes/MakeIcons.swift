// Too Much Chrome — 图标原型绘制（CoreGraphics）
// 产出：4 个概念 × (1024 母版 PNG + AppIcon.iconset)
// 用法：swift icon-prototypes/MakeIcons.swift（在仓库根执行）

import AppKit
import CoreGraphics

// MARK: - 基础设施

let S: CGFloat = 1024
let outRoot = URL(fileURLWithPath: "icon-prototypes")

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

/// 图标底：squircle 内竖向渐变 + 顶部光泽 + 内侧亮边
func drawBase(_ ctx: CGContext, _ top: UInt32, _ bottom: UInt32, glow: UInt32? = nil) {
    let shape = squircle(S / 2, S / 2, S * 0.402)   // 824/1024 内容幅面
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    ctx.drawLinearGradient(
        gradient([top, bottom]),
        start: CGPoint(x: S / 2, y: S), end: CGPoint(x: S / 2, y: 0), options: []
    )
    if let glow {
        ctx.drawRadialGradient(
            gradient([glow], [0.55, 0]),
            startCenter: CGPoint(x: S / 2, y: S * 0.62), startRadius: 0,
            endCenter: CGPoint(x: S / 2, y: S * 0.62), endRadius: S * 0.55, options: []
        )
    }
    // 顶部光泽
    ctx.drawLinearGradient(
        gradient([0xffffff, 0xffffff], [0.22, 0]),
        start: CGPoint(x: S / 2, y: S), end: CGPoint(x: S / 2, y: S * 0.42), options: []
    )
    ctx.restoreGState()

    // 内侧亮边
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.setStrokeColor(color(0xffffff, 0.28))
    ctx.setLineWidth(3)
    ctx.strokePath()
    ctx.restoreGState()
}

/// 光泽圆角贴片（应用方块）：含投影与描边分离
func drawTile(_ ctx: CGContext, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat,
              _ light: UInt32, _ base: UInt32, radius: CGFloat = 28, stroke: Bool = false) {
    let rect = CGRect(x: x, y: y, width: w, height: w)
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.45))
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([light, base]),
        start: CGPoint(x: x, y: y + w), end: CGPoint(x: x, y: y), options: []
    )
    // 上半高光
    ctx.drawLinearGradient(
        gradient([0xffffff, 0xffffff], [0.30, 0]),
        start: CGPoint(x: x, y: y + w), end: CGPoint(x: x, y: y + w * 0.52), options: []
    )
    if stroke {
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setStrokeColor(color(0xffffff, 0.35))
        ctx.setLineWidth(3)
        ctx.addPath(CGPath(
            roundedRect: rect.insetBy(dx: 1.5, dy: 1.5),
            cornerWidth: radius, cornerHeight: radius, transform: nil
        ))
        ctx.strokePath()
    }
    ctx.restoreGState()
}

// MARK: - 概念 A：扫描发现（网格 + 扫描线）

func conceptA() -> CGContext {
    let ctx = makeContext(S)
    drawBase(ctx, 0x2c4a8f, 0x0e1b3e, glow: 0x4a7ede)

    // 3×3 品牌色贴片
    let palette: [(UInt32, UInt32)] = [
        (0x5ac8fa, 0x007aff), (0xc4b5fd, 0x8b5cf6), (0x67e8f9, 0x06b6d4),
        (0xffd60a, 0xff9f0a), (0x7dfba5, 0x34c759), (0xc4b5fd, 0x8b5cf6),
        (0x67e8f9, 0x06b6d4), (0x5ac8fa, 0x007aff), (0xffb86e, 0xff6b2c)
    ]
    let tile: CGFloat = 176, gap: CGFloat = 44
    let gridW = tile * 3 + gap * 2
    let originX = (S - gridW) / 2
    let originY = (S - gridW) / 2
    for row in 0..<3 {
        for col in 0..<3 {
            let (light, base) = palette[row * 3 + col]
            drawTile(ctx, originX + CGFloat(col) * (tile + gap),
                     originY + CGFloat(2 - row) * (tile + gap), tile, light, base)
        }
    }

    // 扫描线（已扫过区域提亮 + 发光横线）
    let lineY = originY + tile + gap + tile * 0.55
    ctx.saveGState()
    ctx.addPath(squircle(S / 2, S / 2, S * 0.402))
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([0x5ac8fa, 0x5ac8fa], [0.26, 0]),
        start: CGPoint(x: 0, y: lineY + 280), end: CGPoint(x: 0, y: lineY), options: []
    )
    for (w, a) in [(34.0, 0.14), (12.0, 0.34), (4.5, 0.98)] {
        ctx.setStrokeColor(color(0x9fe0ff, a))
        ctx.setLineWidth(w)
        ctx.move(to: CGPoint(x: 0, y: lineY))
        ctx.addLine(to: CGPoint(x: S, y: lineY))
        ctx.strokePath()
    }
    ctx.restoreGState()
    return ctx
}

// MARK: - 概念 B：Chromium 原子

func conceptB() -> CGContext {
    let ctx = makeContext(S)
    drawBase(ctx, 0x6fd2ff, 0x0a63e8, glow: 0xaee6ff)

    let cx = S / 2, cy = S / 2
    ctx.saveGState()
    ctx.translateBy(x: cx, y: cy)

    // 三条倾斜轨道
    for i in 0..<3 {
        ctx.saveGState()
        ctx.rotate(by: CGFloat(i) * .pi / 3)
        let rect = CGRect(x: -330, y: -118, width: 660, height: 236)
        ctx.setStrokeColor(color(0xffffff, 0.85))
        ctx.setLineWidth(26)
        ctx.setLineCap(.round)
        ctx.strokeEllipse(in: rect)

        // 电子（各自轨道相位不同）
        let theta = CGFloat(i) * 2.1 + 0.8
        let ex = 330 * cos(theta) * 0.86
        let ey = 118 * sin(theta)
        ctx.setShadow(offset: .zero, blur: 26, color: color(0xe8f7ff, 0.95))
        ctx.setFillColor(color(0xffffff))
        ctx.fillEllipse(in: CGRect(x: ex - 26, y: ey - 26, width: 52, height: 52))
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setFillColor(color(0x5ac8fa, 0.9))
        ctx.fillEllipse(in: CGRect(x: ex - 14, y: ey - 14, width: 28, height: 28))
        ctx.restoreGState()
    }

    // 原子核
    ctx.setShadow(offset: .zero, blur: 60, color: color(0xffffff, 0.75))
    ctx.drawRadialGradient(
        gradient([0xffffff, 0xbfe4ff, 0x4aa8ff]),
        startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 118, options: []
    )
    ctx.restoreGState()
    return ctx
}

// MARK: - 概念 C：堆积超载

func conceptC() -> CGContext {
    let ctx = makeContext(S)
    drawBase(ctx, 0x48484e, 0x1c1c1e, glow: 0x6a6a72)

    // 堆积的贴片（自下而上，顶端两枚外溢）
    struct Chip { let x: CGFloat; let y: CGFloat; let s: CGFloat; let c: (UInt32, UInt32); let r: CGFloat }
    let chips: [Chip] = [
        Chip(x: 262, y: 150, s: 190, c: (0x5ac8fa, 0x007aff), r: -0.06),
        Chip(x: 472, y: 142, s: 200, c: (0xc4b5fd, 0x8b5cf6), r: 0.05),
        Chip(x: 682, y: 158, s: 180, c: (0x67e8f9, 0x06b6d4), r: -0.04),
        Chip(x: 300, y: 342, s: 200, c: (0xffd60a, 0xff9f0a), r: 0.04),
        Chip(x: 512, y: 352, s: 210, c: (0x7dfba5, 0x34c759), r: -0.05),
        Chip(x: 718, y: 340, s: 190, c: (0xffb86e, 0xff6b2c), r: 0.06),
        Chip(x: 402, y: 540, s: 200, c: (0x67e8f9, 0x06b6d4), r: 0.05),
        Chip(x: 612, y: 548, s: 190, c: (0x5ac8fa, 0x007aff), r: -0.06),
        Chip(x: 508, y: 718, s: 180, c: (0xc4b5fd, 0x8b5cf6), r: 0.04),
        // 顶端外溢的两枚
        Chip(x: 780, y: 700, s: 150, c: (0xffd60a, 0xff9f0a), r: 0.35),
        Chip(x: 866, y: 842, s: 116, c: (0xff8f6b, 0xff3b30), r: 0.62)
    ]
    for chip in chips {
        ctx.saveGState()
        ctx.translateBy(x: chip.x + chip.s / 2, y: chip.y + chip.s / 2)
        ctx.rotate(by: chip.r)
        drawTile(ctx, -chip.s / 2, -chip.s / 2, chip.s, chip.c.0, chip.c.1,
                 radius: chip.s * 0.16, stroke: true)
        ctx.restoreGState()
    }
    return ctx
}

// MARK: - 概念 D：放大镜检视

func conceptD() -> CGContext {
    let ctx = makeContext(S)
    drawBase(ctx, 0xbef3ef, 0x3aa8e8, glow: 0xe8fdff)

    let cx: CGFloat = 452, cy: CGFloat = 578, r: CGFloat = 264

    // 镜片内：小网格 + 扫描线（整体裁剪到镜圆内，避免顶到镜框）
    ctx.saveGState()
    ctx.translateBy(x: cx, y: cy)
    ctx.addEllipse(in: CGRect(x: -r + 24, y: -r + 24, width: (r - 24) * 2, height: (r - 24) * 2))
    ctx.clip()
    let mini: [(CGFloat, CGFloat, (UInt32, UInt32))] = [
        (-162, 22, (0x5ac8fa, 0x007aff)),
        (22, 22, (0xc4b5fd, 0x8b5cf6)),
        (-162, -142, (0x67e8f9, 0x06b6d4)),
        (22, -142, (0xffd60a, 0xff9f0a))
    ]
    for (mx, my, c) in mini {
        drawTile(ctx, mx, my, 140, c.0, c.1, radius: 22, stroke: true)
    }
    ctx.setStrokeColor(color(0x0a63e8, 0.75))
    ctx.setLineWidth(12)
    ctx.move(to: CGPoint(x: -r, y: 36))
    ctx.addLine(to: CGPoint(x: r, y: 36))
    ctx.strokePath()
    ctx.restoreGState()

    // 玻璃
    ctx.saveGState()
    ctx.setFillColor(color(0xffffff, 0.14))
    ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    // 弧形高光
    ctx.setStrokeColor(color(0xffffff, 0.85))
    ctx.setLineWidth(20)
    ctx.setLineCap(.round)
    ctx.addArc(center: CGPoint(x: cx, y: cy), radius: r - 58, startAngle: .pi * 0.62, endAngle: .pi * 0.88, clockwise: false)
    ctx.strokePath()

    // 镜框（银色环）
    let ring: CGFloat = 42
    ctx.addEllipse(in: CGRect(x: cx - r - ring / 2, y: cy - r - ring / 2, width: (r + ring / 2) * 2, height: (r + ring / 2) * 2))
    ctx.addEllipse(in: CGRect(x: cx - r + ring / 2, y: cy - r + ring / 2, width: (r - ring / 2) * 2, height: (r - ring / 2) * 2))
    ctx.saveGState()
    ctx.clip(using: .evenOdd)
    ctx.drawLinearGradient(
        gradient([0xf5f7fa, 0x9aa7b8, 0xdfe6ee]),
        start: CGPoint(x: cx - r, y: cy + r), end: CGPoint(x: cx + r, y: cy - r), options: []
    )
    ctx.restoreGState()
    ctx.restoreGState()

    // 手柄（右下 45°，宽度贴合镜框厚度并 tucked 到框下）
    ctx.saveGState()
    ctx.translateBy(x: cx, y: cy)
    ctx.rotate(by: -.pi / 4)
    let handle = CGRect(x: r - 12, y: -29, width: 252, height: 58)
    let handlePath = CGPath(roundedRect: handle, cornerWidth: 29, cornerHeight: 29, transform: nil)
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: color(0x000000, 0.25))
    ctx.addPath(handlePath)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([0xe9eef4, 0x8e9bab, 0xcfd8e2]),
        start: CGPoint(x: 0, y: 29), end: CGPoint(x: 0, y: -29), options: []
    )
    ctx.restoreGState()
    return ctx
}

// MARK: - 概念 E：放大镜 + 品牌图标（检视一堆真实世界应用）
// 镜外散布风格化品牌贴片（降透明 = 下层桌面），镜内 Chrome 三色圆为主角，
// Electron / Tauri 露边，扫描线横过——"在一堆应用里揪出那个 Chrome"。
// 注：均为程序化风格化近似，非官方资源。

/// 品牌贴片：统一圆角方底 + 标志性图形
enum Brand { case chrome, electron, tauri, vscode, slack, generic(UInt32) }

func brandTile(_ ctx: CGContext, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat, _ kind: Brand) {
    // 白底圆角贴片（generic 为品牌色底）
    let rect = CGRect(x: x, y: y, width: s, height: s)
    let path = CGPath(roundedRect: rect, cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: color(0x000000, 0.30))
    ctx.addPath(path)
    ctx.clip()
    let bg: UInt32
    if case .generic(let c) = kind { bg = c } else { bg = 0xf4f6f9 }
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
        ctx.setFillColor(color(0xf4f6f9))
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
        ctx.setFillColor(color(0xf4f6f9))
        ctx.fillEllipse(in: CGRect(x: cx - R * 0.62, y: cy - R * 0.62, width: R * 1.24, height: R * 1.24))
        ctx.setFillColor(color(0x24C8D8))
        ctx.fillEllipse(in: CGRect(x: cx - R * 0.30, y: cy + R * 0.02, width: R * 0.60, height: R * 0.60))

    case .vscode:
        // 蓝底 + 白色双角括号（VS Code 的 <> 语言）
        ctx.setFillColor(color(0x007ACC))
        ctx.fill(rect)
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

    case .slack:
        // 四色井字（Slack）
        let b = s * 0.11, L = s * 0.26, off = s * 0.14
        let groups: [(UInt32, CGFloat)] = [
            (0x36C5F0, 0), (0x2EB67D, 90), (0xECB22E, 180), (0xE01E5A, 270)
        ]
        for (hex, deg) in groups {
            ctx.saveGState()
            ctx.translateBy(x: cx, y: cy)
            ctx.rotate(by: deg * .pi / 180)
            let vbar = CGRect(x: off - b / 2, y: -b / 2, width: b, height: L)
            let hbar = CGRect(x: -b / 2, y: off - b / 2 + b, width: L, height: b)
            ctx.setFillColor(color(hex))
            ctx.addPath(CGPath(roundedRect: vbar, cornerWidth: b / 2, cornerHeight: b / 2, transform: nil))
            ctx.fillPath()
            ctx.setFillColor(color(hex, 0.88))
            ctx.addPath(CGPath(roundedRect: hbar, cornerWidth: b / 2, cornerHeight: b / 2, transform: nil))
            ctx.fillPath()
            ctx.restoreGState()
        }

    case .generic(let hex):
        // 品牌色底 + 白色圆点（凑数的"其他应用"）
        ctx.setFillColor(color(hex))
        ctx.fill(rect)
        ctx.setFillColor(color(0xffffff, 0.9))
        ctx.fillEllipse(in: CGRect(x: cx - s * 0.14, y: cy - s * 0.14, width: s * 0.28, height: s * 0.28))
    }
    ctx.restoreGState()
}

func conceptE() -> CGContext {
    let ctx = makeContext(S)
    drawBase(ctx, 0xbef3ef, 0x3aa8e8, glow: 0xe8fdff)

    let cx: CGFloat = 452, cy: CGFloat = 578, r: CGFloat = 264

    // 镜外：散布的品牌贴片（画完后统一罩暗 = 下层桌面感）
    let outer: [(CGFloat, CGFloat, CGFloat, Brand)] = [
        (96, 90, 168, .generic(0x34C759)),
        (318, 60, 150, .slack),
        (620, 96, 160, .vscode),
        (840, 300, 150, .generic(0xFF9500)),
        (60, 420, 150, .tauri),
        (760, 560, 158, .electron)
    ]
    for (x, y, s, kind) in outer {
        brandTile(ctx, x, y, s, kind)
    }
    ctx.saveGState()
    ctx.addPath(squircle(S / 2, S / 2, S * 0.402))
    ctx.clip()
    ctx.setFillColor(color(0xd6f4fb, 0.38))
    ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
    ctx.restoreGState()

    // 镜内：清晰的品牌图标（裁剪到镜圆）
    ctx.saveGState()
    ctx.translateBy(x: cx, y: cy)
    ctx.addEllipse(in: CGRect(x: -r + 16, y: -r + 16, width: (r - 16) * 2, height: (r - 16) * 2))
    ctx.clip()
    // Chrome 主角（占镜面约 2/3，聚焦冲击力）
    brandTile(ctx, -206, -92, 336, .chrome)
    // Electron 右下露半个（克制的配角）
    brandTile(ctx, 120, -226, 150, .electron)
    // Tauri 左上露角
    brandTile(ctx, -210, 140, 132, .tauri)
    // 扫描线横过主角
    ctx.setStrokeColor(color(0x0a63e8, 0.8))
    ctx.setLineWidth(12)
    ctx.move(to: CGPoint(x: -r, y: 44))
    ctx.addLine(to: CGPoint(x: r, y: 44))
    ctx.strokePath()
    for (w, a) in [(30.0, 0.12), (5.0, 0.5)] {
        ctx.setStrokeColor(color(0x9fe0ff, a))
        ctx.setLineWidth(w)
        ctx.move(to: CGPoint(x: -r, y: 44))
        ctx.addLine(to: CGPoint(x: r, y: 44))
        ctx.strokePath()
    }
    ctx.restoreGState()

    // 玻璃 + 高光弧 + 银框 + 手柄（沿用概念 D 的修复版）
    ctx.setFillColor(color(0xffffff, 0.10))
    ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    ctx.setStrokeColor(color(0xffffff, 0.85))
    ctx.setLineWidth(20)
    ctx.setLineCap(.round)
    ctx.addArc(center: CGPoint(x: cx, y: cy), radius: r - 58, startAngle: .pi * 0.62, endAngle: .pi * 0.88, clockwise: false)
    ctx.strokePath()

    let ring: CGFloat = 42
    ctx.addEllipse(in: CGRect(x: cx - r - ring / 2, y: cy - r - ring / 2, width: (r + ring / 2) * 2, height: (r + ring / 2) * 2))
    ctx.addEllipse(in: CGRect(x: cx - r + ring / 2, y: cy - r + ring / 2, width: (r - ring / 2) * 2, height: (r - ring / 2) * 2))
    ctx.saveGState()
    ctx.clip(using: .evenOdd)
    ctx.drawLinearGradient(
        gradient([0xf5f7fa, 0x9aa7b8, 0xdfe6ee]),
        start: CGPoint(x: cx - r, y: cy + r), end: CGPoint(x: cx + r, y: cy - r), options: []
    )
    ctx.restoreGState()

    ctx.saveGState()
    ctx.translateBy(x: cx, y: cy)
    ctx.rotate(by: -.pi / 4)
    let handle = CGRect(x: r - 12, y: -29, width: 252, height: 58)
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: color(0x000000, 0.25))
    ctx.addPath(CGPath(roundedRect: handle, cornerWidth: 29, cornerHeight: 29, transform: nil))
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([0xe9eef4, 0x8e9bab, 0xcfd8e2]),
        start: CGPoint(x: 0, y: 29), end: CGPoint(x: 0, y: -29), options: []
    )
    ctx.restoreGState()
    return ctx
}

// MARK: - 导出（母版 + iconset + 拼图）

let iconsetSizes: [(CGFloat, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png")
]

func writeIconset(_ ctx: CGContext, dir: URL) {
    guard let master = ctx.makeImage() else { fatalError() }
    let iconsetDir = dir.appendingPathComponent("AppIcon.iconset")
    for (size, name) in iconsetSizes {
        let small = makeContext(size)
        small.interpolationQuality = .high
        small.draw(master, in: CGRect(x: 0, y: 0, width: size, height: size))
        savePNG(small, iconsetDir.appendingPathComponent(name))
    }
}

let concepts: [(String, () -> CGContext)] = [
    ("A-scanline", conceptA),
    ("B-atom", conceptB),
    ("C-pile", conceptC),
    ("D-lens", conceptD),
    ("E-brand-lens", conceptE)
]

var masters: [(String, CGImage)] = []
for (name, draw) in concepts {
    let ctx = draw()
    let dir = outRoot.appendingPathComponent(name)
    savePNG(ctx, dir.appendingPathComponent("master.png"))
    writeIconset(ctx, dir: dir)
    masters.append((name, ctx.makeImage()!))
    print("✓ \(name)")
}

// 拼图：2 列 × 自适应行数对比总览
let count = masters.count
let rows = Int(ceil(Double(count) / 2))
let sheetSize: CGFloat = 24 * (CGFloat(rows) + 1) + CGFloat(rows) * 1024
let sheet = makeContext(sheetSize)
sheet.setFillColor(color(0x111114))
sheet.fill(CGRect(x: 0, y: 0, width: sheetSize, height: sheetSize))
for (i, (_, img)) in masters.enumerated() {
    let col = CGFloat(i % 2), row = CGFloat(i / 2)
    let cell = 1024.0
    let x = 24 + col * (cell + 24)
    let y = 24 + (CGFloat(rows) - 1 - row) * (cell + 24)   // CG 坐标 y 向上
    sheet.interpolationQuality = .high
    sheet.draw(img, in: CGRect(x: x, y: y, width: cell, height: cell))
}
savePNG(sheet, outRoot.appendingPathComponent("overview.png"))
print("✓ overview.png")
