//
//  Danmaku.swift
//  KazumiTV
//
//  Danmaku (Bullet Comments) Model
//

import Foundation
import SwiftUI

struct DanmakuItem: Identifiable, Equatable, Hashable {
    let id: UUID
    let text: String
    let time: TimeInterval
    let type: DanmakuType
    let color: Color
    let source: String
    let yPosition: CGFloat
    let duration: TimeInterval

    init(
        id: UUID = UUID(),
        text: String,
        time: TimeInterval,
        type: DanmakuType,
        color: Color = .white,
        source: String = "",
        yPosition: CGFloat = 0.5,
        duration: TimeInterval = 8.0
    ) {
        self.id = id
        self.text = text
        self.time = time
        self.type = type
        self.color = color
        self.source = source
        self.yPosition = yPosition
        self.duration = duration
    }

    init(from danDanPlay: DanDanPlayComment) {
        self.id = UUID()
        self.text = danDanPlay.text
        self.time = danDanPlay.time
        self.type = DanmakuType(rawValue: danDanPlay.type) ?? .scroll
        self.color = danDanPlay.color
        self.source = danDanPlay.source
        self.yPosition = 0.5
        self.duration = 8.0
    }
}

enum DanmakuType: Int, Equatable, Hashable {
    case scroll = 1      // 滚动弹幕
    case top = 5         // 顶部固定弹幕
    case bottom = 4      // 底部固定弹幕

    var rawValue: Int {
        switch self {
        case .scroll: return 1
        case .top: return 5
        case .bottom: return 4
        }
    }

    init?(rawValue: Int) {
        switch rawValue {
        case 1: self = .scroll
        case 4: self = .bottom
        case 5: self = .top
        default: self = .scroll
        }
    }
}

// MARK: - DanDanPlay API Response
struct DanDanPlayResponse: Codable {
    let id: Int?
    let total: Int?
    let comments: [DanDanPlayComment]
}

struct DanDanPlayComment: Codable {
    let p: String  // time,type,color,source
    let m: String  // message text

    var time: TimeInterval {
        let parts = p.split(separator: ",")
        return Double(parts[0]) ?? 0
    }

    var type: Int {
        let parts = p.split(separator: ",")
        return Int(parts[1]) ?? 1
    }

    var color: Color {
        let parts = p.split(separator: ",")
        let colorValue = Int(parts[2]) ?? 0xFFFFFF
        return Color(
            red: Double((colorValue >> 16) & 0xFF) / 255.0,
            green: Double((colorValue >> 8) & 0xFF) / 255.0,
            blue: Double(colorValue & 0xFF) / 255.0
        )
    }

    var source: String {
        let parts = p.split(separator: ",")
        return parts.count > 3 ? String(parts[3]) : ""
    }

    var text: String { m }
}

extension DanmakuItem {
    static let samples: [DanmakuItem] = [
        DanmakuItem(text: "第一发弹幕", time: 1.0, type: .scroll),
        DanmakuItem(text: "顶部弹幕", time: 2.0, type: .top),
        DanmakuItem(text: "底部弹幕", time: 3.0, type: .bottom),
        DanmakuItem(text: "彩色弹幕", time: 4.0, type: .scroll, color: .red),
        DanmakuItem(text: "长弹幕测试", time: 5.0, type: .scroll)
    ]
}
