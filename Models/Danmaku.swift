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
}

// MARK: - DanDanPlay API Response
struct DanDanPlayResponse: Decodable {
    let id: Int?
    let total: Int?
    let comments: [DanDanPlayComment]

    enum CodingKeys: String, CodingKey {
        case id
        case total
        case comments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id)
        total = try container.decodeIfPresent(Int.self, forKey: .total)
        comments = try container.decodeIfPresent([DanDanPlayComment].self, forKey: .comments) ?? []
    }
}

struct DanDanPlayComment: Decodable {
    let p: String  // time,type,color,source
    let m: String  // message text

    private var parts: [Substring] {
        p.split(separator: ",", omittingEmptySubsequences: false)
    }

    var time: TimeInterval {
        guard let value = parts.first else { return 0 }
        return Double(value) ?? 0
    }

    var type: Int {
        guard parts.count > 1 else { return DanmakuType.scroll.rawValue }
        return Int(parts[1]) ?? DanmakuType.scroll.rawValue
    }

    var color: Color {
        let colorValue: Int
        if parts.count > 2 {
            colorValue = Int(parts[2]) ?? 0xFFFFFF
        } else {
            colorValue = 0xFFFFFF
        }

        return Color(
            red: Double((colorValue >> 16) & 0xFF) / 255.0,
            green: Double((colorValue >> 8) & 0xFF) / 255.0,
            blue: Double(colorValue & 0xFF) / 255.0
        )
    }

    var source: String {
        return parts.count > 3 ? String(parts[3]) : ""
    }

    var text: String { m }
}

extension Array where Element == DanmakuItem {
    func removingNearbyDuplicates(timeWindow: TimeInterval = 5) -> [DanmakuItem] {
        var acceptedTimesByText: [String: [TimeInterval]] = [:]
        var result: [DanmakuItem] = []

        for item in sorted(by: { $0.time < $1.time }) {
            let key = item.normalizedTextForDeduplication
            let acceptedTimes = acceptedTimesByText[key] ?? []
            let hasNearbyDuplicate = acceptedTimes.contains { abs($0 - item.time) <= timeWindow }

            if hasNearbyDuplicate {
                continue
            }

            result.append(item)
            acceptedTimesByText[key, default: []].append(item.time)
        }

        return result
    }
}

private extension DanmakuItem {
    var normalizedTextForDeduplication: String {
        let transformed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text

        let scalars = transformed.unicodeScalars.filter { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar) &&
            !CharacterSet.punctuationCharacters.contains(scalar) &&
            !CharacterSet.symbols.contains(scalar)
        }

        let normalized = String(String.UnicodeScalarView(scalars))
        return normalized.isEmpty ? text : normalized
    }
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
