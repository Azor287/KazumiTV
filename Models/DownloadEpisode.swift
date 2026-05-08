//
//  DownloadEpisode.swift
//  KazumiTV
//
//  Download Episode Model
//

import Foundation

struct DownloadEpisode: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let bangumiId: Int
    let bangumiName: String
    let episodeNumber: Int
    let episodeName: String
    let m3u8URL: URL
    let quality: String
    let pluginName: String
    var status: DownloadStatus
    var progress: Double
    var totalBytes: Int64
    var downloadedBytes: Int64
    var localPath: URL?
    let createdAt: Date
    var updatedAt: Date

    enum DownloadStatus: Int, Codable {
        case pending = 0
        case downloading = 1
        case paused = 2
        case completed = 3
        case failed = 4
    }

    init(
        id: String = UUID().uuidString,
        bangumiId: Int,
        bangumiName: String,
        episodeNumber: Int,
        episodeName: String,
        m3u8URL: URL,
        quality: String,
        pluginName: String,
        status: DownloadStatus = .pending,
        progress: Double = 0,
        totalBytes: Int64 = 0,
        downloadedBytes: Int64 = 0,
        localPath: URL? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.bangumiId = bangumiId
        self.bangumiName = bangumiName
        self.episodeNumber = episodeNumber
        self.episodeName = episodeName
        self.m3u8URL = m3u8URL
        self.quality = quality
        self.pluginName = pluginName
        self.status = status
        self.progress = progress
        self.totalBytes = totalBytes
        self.downloadedBytes = downloadedBytes
        self.localPath = localPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayName: String {
        "第\(episodeNumber)话 \(episodeName)"
    }

    var progressText: String {
        String(format: "%.1f%%", progress * 100)
    }

    var sizeText: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        if totalBytes > 0 {
            return "\(formatter.string(fromByteCount: downloadedBytes)) / \(formatter.string(fromByteCount: totalBytes))"
        }
        return formatter.string(fromByteCount: downloadedBytes)
    }
}

extension DownloadEpisode {
    static let sample = DownloadEpisode(
        bangumiId: 1,
        bangumiName: "测试动画",
        episodeNumber: 1,
        episodeName: "第一话",
        m3u8URL: URL(string: "https://example.com/video.m3u8")!,
        quality: "1080P",
        pluginName: "DM84",
        status: .downloading,
        progress: 0.45,
        totalBytes: 500_000_000,
        downloadedBytes: 225_000_000
    )
}
