//
//  VideoSource.swift
//  KazumiTV
//
//  Video Source Model
//

import Foundation

struct VideoSource: Equatable, Hashable {
    let url: URL
    let quality: String
    let pluginName: String
    let referer: String?
    let headers: [String: String]

    init(url: URL, quality: String = "默认", pluginName: String, referer: String? = nil, headers: [String: String] = [:]) {
        self.url = url
        self.quality = quality
        self.pluginName = pluginName
        self.referer = referer
        self.headers = headers
    }

    var isM3U8: Bool {
        url.pathExtension.lowercased() == "m3u8"
    }

    var isMP4: Bool {
        url.pathExtension.lowercased() == "mp4"
    }
}

// MARK: - M3U8 Playlist
struct M3U8Playlist {
    let segments: [M3U8Segment]
    let duration: TimeInterval
    let resolution: (width: Int, height: Int)?

    var totalDuration: TimeInterval {
        segments.reduce(0) { $0 + $1.duration }
    }
}

struct M3U8Segment: Equatable, Hashable {
    let url: URL
    let duration: TimeInterval
    let sequence: Int
    let isEncrypted: Bool
    let keyURL: URL?
    let iv: Data?

    init(url: URL, duration: TimeInterval, sequence: Int, isEncrypted: Bool = false, keyURL: URL? = nil, iv: Data? = nil) {
        self.url = url
        self.duration = duration
        self.sequence = sequence
        self.isEncrypted = isEncrypted
        self.keyURL = keyURL
        self.iv = iv
    }
}

// MARK: - Sample Data
extension VideoSource {
    static let sample = VideoSource(
        url: URL(string: "https://example.com/video.m3u8")!,
        quality: "1080P",
        pluginName: "DM84",
        referer: "https://dmbus.cc/"
    )

    static let samples: [VideoSource] = [
        VideoSource(url: URL(string: "https://example.com/1080p.m3u8")!, quality: "1080P", pluginName: "DM84"),
        VideoSource(url: URL(string: "https://example.com/720p.m3u8")!, quality: "720P", pluginName: "DM84"),
        VideoSource(url: URL(string: "https://example.com/480p.m3u8")!, quality: "480P", pluginName: "DM84")
    ]
}
