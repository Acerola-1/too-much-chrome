import SwiftUI

// MARK: - 应用类型与样例数据（与 pages/index.html 同源）

enum AppType: String, CaseIterable {
    case electron
    case tauri
    case wails

    var base: Color {
        switch self {
        case .electron: Color(red: 0, green: 0.478, blue: 1)        // #007aff
        case .tauri:   Color(red: 0.545, green: 0.361, blue: 0.965) // #8b5cf6
        case .wails:   Color(red: 0.024, green: 0.714, blue: 0.831) // #06b6d4
        }
    }

    var light: Color {
        switch self {
        case .electron: Color(red: 0.353, green: 0.784, blue: 0.980) // #5ac8fa
        case .tauri:   Color(red: 0.769, green: 0.710, blue: 0.992) // #c4b5fd
        case .wails:   Color(red: 0.404, green: 0.910, blue: 0.976) // #67e8f9
        }
    }

    var label: String { rawValue.capitalized }
}

struct SampleApp: Identifiable {
    let id: Int
    let name: String
    let type: AppType
    let bodyMB: Int
    let dataMB: Int

    var totalMB: Int { bodyMB + dataMB }

    var sizeText: String {
        totalMB >= 1024
            ? String(format: "%.1f GB", Double(totalMB) / 1024)
            : "\(totalMB) MB"
    }
}

enum SampleData {
    static let apps: [SampleApp] = [
        .init(id: 0, name: "VS Code", type: .electron, bodyMB: 380, dataMB: 620),
        .init(id: 1, name: "Slack", type: .electron, bodyMB: 320, dataMB: 540),
        .init(id: 2, name: "Discord", type: .electron, bodyMB: 290, dataMB: 780),
        .init(id: 3, name: "Figma", type: .electron, bodyMB: 310, dataMB: 260),
        .init(id: 4, name: "Notion", type: .electron, bodyMB: 350, dataMB: 410),
        .init(id: 5, name: "Spotify", type: .electron, bodyMB: 280, dataMB: 350),
        .init(id: 6, name: "Trello", type: .electron, bodyMB: 260, dataMB: 95),
        .init(id: 7, name: "Postman", type: .electron, bodyMB: 420, dataMB: 310),
        .init(id: 8, name: "Zoom", type: .electron, bodyMB: 340, dataMB: 220),
        .init(id: 9, name: "Skype", type: .electron, bodyMB: 300, dataMB: 180),
        .init(id: 10, name: "Twitch", type: .electron, bodyMB: 270, dataMB: 120),
        .init(id: 11, name: "WhatsApp", type: .electron, bodyMB: 290, dataMB: 240),
        .init(id: 12, name: "Telegram", type: .electron, bodyMB: 250, dataMB: 380),
        .init(id: 13, name: "Signal", type: .electron, bodyMB: 280, dataMB: 160),
        .init(id: 14, name: "Minecraft Launcher", type: .electron, bodyMB: 330, dataMB: 90),
        .init(id: 15, name: "GitHub Desktop", type: .electron, bodyMB: 360, dataMB: 140),
        .init(id: 16, name: "Atom", type: .electron, bodyMB: 310, dataMB: 210),
        .init(id: 17, name: "1Password", type: .electron, bodyMB: 270, dataMB: 85),
        .init(id: 18, name: "Dropbox", type: .electron, bodyMB: 400, dataMB: 450),
        .init(id: 19, name: "Evernote", type: .electron, bodyMB: 350, dataMB: 520),
        .init(id: 20, name: "Asana", type: .electron, bodyMB: 260, dataMB: 110),
        .init(id: 21, name: "Basecamp", type: .electron, bodyMB: 255, dataMB: 75),
        .init(id: 22, name: "Linear", type: .electron, bodyMB: 320, dataMB: 200),
        .init(id: 23, name: "Insomnia", type: .electron, bodyMB: 340, dataMB: 130),
        .init(id: 24, name: "MongoDB Compass", type: .electron, bodyMB: 380, dataMB: 95),
        .init(id: 25, name: "Redis Insight", type: .electron, bodyMB: 355, dataMB: 88),
        .init(id: 26, name: "Docker Desktop", type: .electron, bodyMB: 700, dataMB: 800),
        .init(id: 27, name: "Arc", type: .electron, bodyMB: 450, dataMB: 640),
        .init(id: 28, name: "Spacedrive", type: .tauri, bodyMB: 28, dataMB: 120),
        .init(id: 29, name: "Lapce", type: .tauri, bodyMB: 24, dataMB: 60),
        .init(id: 30, name: "Prism Launcher", type: .tauri, bodyMB: 30, dataMB: 210),
        .init(id: 31, name: "Espanso", type: .tauri, bodyMB: 18, dataMB: 35),
        .init(id: 32, name: "Rayso", type: .wails, bodyMB: 22, dataMB: 40),
        .init(id: 33, name: "Vesktop", type: .wails, bodyMB: 26, dataMB: 150),
        .init(id: 34, name: "Itch Manager", type: .wails, bodyMB: 20, dataMB: 55)
    ]

    static let count = apps.count
    static let maxMB = apps.map(\.totalMB).max() ?? 1
    static let sumMB = apps.reduce(0) { $0 + $1.totalMB }
    static let sumGBText = String(format: "%.1f", Double(sumMB) / 1024)

    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" })
        guard let first = words.first else { return "?" }
        if words.count == 1 { return String(first.prefix(1)).uppercased() }
        return (String(first.prefix(1)) + String(words[1].prefix(1))).uppercased()
    }
}

// MARK: - 网格解析几何
// 图标全部使用固定单元格尺寸，使槽位位置可以脱离布局解析计算，
// 各概念的偏移动画（簇位置 / 弹射峰值 / 雷达角度）由此获得精确坐标。

enum GridGeom {
    static let cols = 7
    static let rows = 5
    static let cellW: CGFloat = 92
    static let cellH: CGFloat = 100
    static let hGap: CGFloat = 14
    static let vGap: CGFloat = 10

    static var width: CGFloat { CGFloat(cols) * cellW + CGFloat(cols - 1) * hGap }
    static var height: CGFloat { CGFloat(rows) * cellH + CGFloat(rows - 1) * vGap }

    /// 槽位中心相对网格中心的偏移
    static func slotOffset(_ index: Int) -> CGSize {
        let col = CGFloat(index % cols)
        let row = CGFloat(index / cols)
        return CGSize(
            width: (col - CGFloat(cols - 1) / 2) * (cellW + hGap),
            height: (row - CGFloat(rows - 1) / 2) * (cellH + vGap)
        )
    }

    static var maxSlotDistance: CGFloat {
        (0..<cols * rows).map { slot in
            hypot(slotOffset(slot).width, slotOffset(slot).height)
        }.max() ?? 1
    }

    /// 雷达概念：槽位相对扫描起点（-90°，即 9 点钟方向）的顺时针角度
    static func radarRelAngle(_ index: Int) -> Double {
        let o = slotOffset(index)
        let a = atan2(Double(o.height), Double(o.width)) * 180 / .pi + 180
        return (a.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }
}
