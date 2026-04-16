//
//  VideoService.swift
//  KazumiTV
//
//  Video Service Layer
//

import Foundation

// MARK: - Video Service Protocol
protocol VideoServiceProtocol {
    func fetchFeaturedVideos() async throws -> [Video]
    func fetchRecentVideos() async throws -> [Video]
    func fetchVideo(id: String) async throws -> Video
    func searchVideos(query: String) async throws -> [Video]
}

// MARK: - Video Service
final class VideoService: VideoServiceProtocol {

    private let networkClient: NetworkClientProtocol
    private let baseURL = "https://api.kazumitv.com/v1"

    init(networkClient: NetworkClientProtocol = NetworkClient()) {
        self.networkClient = networkClient
    }

    func fetchFeaturedVideos() async throws -> [Video] {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 500_000_000)
        return Video.samples
    }

    func fetchRecentVideos() async throws -> [Video] {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 300_000_000)
        return Video.samples.shuffled()
    }

    func fetchVideo(id: String) async throws -> Video {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 200_000_000)
        guard let video = Video.samples.first(where: { $0.id == id }) else {
            throw VideoServiceError.videoNotFound
        }
        return video
    }

    func searchVideos(query: String) async throws -> [Video] {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 400_000_000)
        return Video.samples.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.category.localizedCaseInsensitiveContains(query)
        }
    }
}

// MARK: - Video Service Error
enum VideoServiceError: LocalizedError {
    case videoNotFound
    case networkError(underlying: Error)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .videoNotFound:
            return "Video not found"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}
