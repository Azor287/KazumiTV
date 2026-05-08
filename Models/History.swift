//
//  History.swift
//  KazumiTV
//
//  Watch History Model
//

import Foundation

struct History: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let bangumiId: Int
    let episodeId: Int
    let episodeNumber: Int
    let episodeName: String
    let bangumiName: String
    let bangumiImage: String
    let progress: TimeInterval
    let duration: TimeInterval
    let lastWatchedAt: Date
    let source: String
    let sourceURL: String
    let sourceName: String

    init(
        id: String = UUID().uuidString,
        bangumiId: Int,
        episodeId: Int,
        episodeNumber: Int,
        episodeName: String,
        bangumiName: String,
        bangumiImage: String,
        progress: TimeInterval,
        duration: TimeInterval,
        lastWatchedAt: Date = Date(),
        source: String = "",
        sourceURL: String = "",
        sourceName: String = ""
    ) {
        self.id = id
        self.bangumiId = bangumiId
        self.episodeId = episodeId
        self.episodeNumber = episodeNumber
        self.episodeName = episodeName
        self.bangumiName = bangumiName
        self.bangumiImage = bangumiImage
        self.progress = progress
        self.duration = duration
        self.lastWatchedAt = lastWatchedAt
        self.source = source
        self.sourceURL = sourceURL
        self.sourceName = sourceName
    }

    var progressPercentage: Double {
        guard duration > 0 else { return 0 }
        return min(progress / duration, 1.0)
    }

    var progressText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: lastWatchedAt)
    }

    var remainingTime: TimeInterval {
        max(duration - progress, 0)
    }

    var remainingTimeText: String {
        let remaining = remainingTime
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return "\(minutes)分\(seconds)秒"
    }

    var displayEpisodeName: String {
        let trimmedName = episodeName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "第\(episodeNumber)话" : trimmedName
    }

    var sourceDisplayName: String {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedSource.isEmpty ? "未知来源" : trimmedSource
    }

    var playbackProgressText: String {
        guard duration > 0 else {
            return "已观看 \(Self.formatDuration(progress))"
        }

        return "\(Self.formatDuration(progress)) / \(Self.formatDuration(duration))"
    }

    var relativeWatchedText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastWatchedAt, relativeTo: Date())
    }

    var posterURL: URL? {
        Self.normalizedURL(from: bangumiImage)
    }

    var bangumi: Bangumi {
        let normalizedImage = Self.normalizedURLString(from: bangumiImage)
        var images: [String: String] = [:]
        if !normalizedImage.isEmpty {
            images = [
                "large": normalizedImage,
                "common": normalizedImage,
                "grid": normalizedImage,
                "medium": normalizedImage
            ]
        }

        return Bangumi(
            id: bangumiId,
            type: 2,
            name: bangumiName,
            nameCn: "",
            summary: "",
            airDate: "",
            airWeekday: 0,
            rank: 0,
            images: images,
            tags: [],
            alias: [],
            ratingScore: 0,
            votes: 0,
            votesCount: [],
            info: ""
        )
    }

    var searchItem: SearchItem? {
        let trimmedSourceURL = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSourceURL.isEmpty, !trimmedSource.isEmpty else { return nil }

        let displaySourceName = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return SearchItem(
            id: "\(trimmedSource)|\(trimmedSourceURL)",
            name: displaySourceName.isEmpty ? bangumiName : displaySourceName,
            src: trimmedSourceURL,
            pluginName: trimmedSource,
            imageURL: posterURL
        )
    }

    private static func formatDuration(_ value: TimeInterval) -> String {
        let clamped = max(0, Int(value))
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let seconds = clamped % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%d:%02d", minutes, seconds)
    }

    private static func normalizedURL(from value: String) -> URL? {
        let normalized = normalizedURLString(from: value)
        guard !normalized.isEmpty else { return nil }
        return URL(string: normalized)
    }

    private static func normalizedURLString(from value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("//") {
            trimmed = "https:" + trimmed
        } else if trimmed.hasPrefix("http://") {
            trimmed = "https://" + trimmed.dropFirst("http://".count)
        }
        return trimmed
    }
}

extension History {
    static let sample = History(
        bangumiId: 1,
        episodeId: 1,
        episodeNumber: 5,
        episodeName: "第五话",
        bangumiName: "测试动画",
        bangumiImage: "https://bgm.tv/img/no_icon_subject.png",
        progress: 600,
        duration: 1440,
        source: "DM84",
        sourceURL: "https://example.com/anime/1",
        sourceName: "测试动画"
    )
}
