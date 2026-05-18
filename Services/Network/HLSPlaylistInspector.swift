//
//  HLSPlaylistInspector.swift
//  KazumiTV
//

import Foundation

struct HLSPlaylistInspection {
    let isPlaylist: Bool
    let isLikelyPlayable: Bool
    let reason: String?
}

enum HLSPlaylistInspector {
    private static let maximumImagePlaceholderDuration: Double = 120

    static func inspect(_ text: String, url: URL? = nil) -> HLSPlaylistInspection {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#EXTM3U") else {
            return HLSPlaylistInspection(isPlaylist: false, isLikelyPlayable: false, reason: "response is not HLS")
        }

        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let lowercasedURL = url?.absoluteString.lowercased() ?? ""
        if lowercasedURL.contains("/zhuanma/") || lowercasedURL.contains("zhuanma/index.m3u8") {
            return HLSPlaylistInspection(isPlaylist: true, isLikelyPlayable: false, reason: "transcoding placeholder playlist")
        }

        let isMasterPlaylist = lines.contains { $0.hasPrefix("#EXT-X-STREAM-INF") }
        if isMasterPlaylist {
            return HLSPlaylistInspection(isPlaylist: true, isLikelyPlayable: true, reason: nil)
        }

        let hasEndList = lines.contains("#EXT-X-ENDLIST")
        let mediaLines = lines.filter { !$0.hasPrefix("#") }
        let durations = lines.compactMap(extinfDuration)
        let totalDuration = durations.reduce(0, +)

        if hasEndList,
           totalDuration > 0,
           totalDuration < maximumImagePlaceholderDuration,
           !mediaLines.isEmpty,
           mediaLines.allSatisfy(isImageSegment) {
            return HLSPlaylistInspection(isPlaylist: true, isLikelyPlayable: false, reason: "image segment placeholder playlist")
        }

        let lowercasedText = text.lowercased()
        if lowercasedText.contains("zhuanma") || lowercasedText.contains("transcod") {
            return HLSPlaylistInspection(isPlaylist: true, isLikelyPlayable: false, reason: "transcoding placeholder playlist")
        }

        return HLSPlaylistInspection(isPlaylist: true, isLikelyPlayable: true, reason: nil)
    }

    private static func isImageSegment(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        return lowercased.contains(".gif")
            || lowercased.contains(".jpg")
            || lowercased.contains(".jpeg")
            || lowercased.contains(".png")
            || lowercased.contains(".webp")
    }

    private static func extinfDuration(from line: String) -> Double? {
        guard line.hasPrefix("#EXTINF:") else { return nil }
        let raw = line
            .dropFirst("#EXTINF:".count)
            .split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? ""
        return Double(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
