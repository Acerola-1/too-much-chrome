#!/usr/bin/env swift
// Too Much Chrome — 从 AppIcon.icon 分层源合成扁平 AppIcon.icns
// 分层源（background-dark + front，macOS 26 Icon Composer）在 macOS 26 上由系统
// 实时叠加液态玻璃光学；此处平铺合成单层图，供 .app 打包与官网/README 使用。
// 用法：swift scripts/render_icon.swift [输出目录]（默认 .build/icon-render）
// 产物：master.png（1024 合成图）、AppIcon.iconset/（10 尺寸）、AppIcon.icns

import Foundation
import CoreGraphics
import ImageIO

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let srcDir = repoRoot.appendingPathComponent("AppIcon.icon/Assets")
let outDir = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : repoRoot.appendingPathComponent(".build/icon-render")

func makeContext(_ size: CGFloat) -> CGContext {
    guard let ctx = CGContext(
        data: nil, width: Int(size), height: Int(size),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("context 创建失败") }
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    return ctx
}

func loadPNG(_ name: String) -> CGImage {
    let url = srcDir.appendingPathComponent(name) as CFURL
    guard let src = CGImageSourceCreateWithURL(url, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else { fatalError("无法读取 \(name)") }
    return img
}

func savePNG(_ img: CGImage, to url: URL) {
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, "public.png" as CFString, 1, nil)
    else { fatalError("PNG 写入失败: \(url.path)") }
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

func downsample(_ img: CGImage, to px: Int) -> CGImage {
    let ctx = makeContext(CGFloat(px))
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: px, height: px))
    guard let out = ctx.makeImage() else { fatalError("下采样失败 \(px)") }
    return out
}

// ---- 合成 1024 master：放大镜前层覆盖在碳黑背景上 ----
let ctx = makeContext(1024)
let bg = loadPNG("background-dark.png")
let fg = loadPNG("front.png")
ctx.draw(bg, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
ctx.draw(fg, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
guard let master = ctx.makeImage() else { fatalError("master 合成失败") }

let iconsetDir = outDir.appendingPathComponent("AppIcon.iconset")
let sizes: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for size in sizes {
    savePNG(downsample(master, to: size.px), to: iconsetDir.appendingPathComponent(size.name))
}
savePNG(master, to: outDir.appendingPathComponent("master.png"))

// ---- iconutil 出 icns ----
let icnsURL = outDir.appendingPathComponent("AppIcon.icns")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsURL.path]
try? process.run()
process.waitUntilExit()
guard FileManager.default.fileExists(atPath: icnsURL.path) else {
    fatalError("iconutil 失败，未产出 AppIcon.icns")
}
print("✓ \(icnsURL.path)")
