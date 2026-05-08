//
//  AVPlayerController.swift
//  KazumiTV
//
//  AVPlayer Controller with pub/sub for playback state
//

import Foundation
import AVFoundation
import Combine

@MainActor
class AVPlayerController: ObservableObject {
    // MARK: - Published Properties
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isBuffering = false
    @Published var playbackRate: Float = 1.0
    @Published var volume: Float = 1.0
    @Published var error: Error?

    // MARK: - Player
    private(set) var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var pendingSeekTime: TimeInterval?
    private var initialSeekTime: TimeInterval?
    private var didApplyInitialSeek = false

    // MARK: - Current Source
    private(set) var currentSource: VideoSource?

    // MARK: - Settings
    private let settings = SettingsRepository.shared

    // MARK: - Init

    init() {}

    // MARK: - Load Video

    func loadVideo(source: VideoSource, resumePosition: TimeInterval? = nil) {
        cleanup()

        currentSource = source
        initialSeekTime = initialPosition(for: source.url, resumePosition: resumePosition)
        didApplyInitialSeek = false

        var options: [String: Any] = [:]

        // Add headers for AVURLAsset
        if !source.headers.isEmpty {
            options["AVURLAssetHTTPHeaderFieldsKey"] = source.headers
        }

        // Add referer if present
        if let referer = source.referer {
            var headers = source.headers
            headers["Referer"] = referer
            options["AVURLAssetHTTPHeaderFieldsKey"] = headers
        }

        if let mimeType = inferredMIMEType(for: source.url) {
            options["AVURLAssetOutOfBandMIMETypeKey"] = mimeType
            print("AVPlayerController.loadVideo: 使用 MIME type \(mimeType), url = \(source.url.absoluteString)")
        }

        let asset = AVURLAsset(url: source.url, options: options)
        playerItem = AVPlayerItem(asset: asset)

        player = AVPlayer(playerItem: playerItem)
        player?.volume = volume
        player?.rate = playbackRate

        setupObservers()
    }

    func loadVideo(url: URL, headers: [String: String] = [:]) {
        let source = VideoSource(url: url, quality: "默认", pluginName: "", referer: nil, headers: headers)
        loadVideo(source: source)
    }

    // MARK: - Playback Controls

    func play() {
        player?.play()
        player?.rate = playbackRate
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to time: TimeInterval) {
        let upperBound = duration > 0 ? duration : time
        let targetTime = max(0, min(time, upperBound))
        pendingSeekTime = targetTime
        currentTime = targetTime

        let cmTime = CMTime(seconds: targetTime, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard finished else { return }
            Task { @MainActor in
                if let pending = self?.pendingSeekTime, abs(pending - targetTime) < 0.1 {
                    self?.pendingSeekTime = nil
                }
            }
        }
    }

    func seekForward(seconds: TimeInterval = 5) {
        let baseTime = pendingSeekTime ?? currentTime
        let upperBound = duration > 0 ? duration : baseTime + seconds
        let newTime = min(baseTime + seconds, upperBound)
        seek(to: newTime)
    }

    func seekBackward(seconds: TimeInterval = 5) {
        let baseTime = pendingSeekTime ?? currentTime
        let newTime = max(baseTime - seconds, 0)
        seek(to: newTime)
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying {
            player?.rate = rate
        }
    }

    func setVolume(_ volume: Float) {
        self.volume = max(0, min(1, volume))
        player?.volume = self.volume
    }

    // MARK: - Observers

    private func setupObservers() {
        guard let player = player, let playerItem = playerItem else { return }

        // Time observer
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self = self else { return }
                guard self.pendingSeekTime == nil else { return }
                self.currentTime = time.seconds

                // Save position periodically
                if let url = self.currentSource?.url {
                    self.savePosition(url: url, position: time.seconds)
                }
            }
        }

        // Duration
        playerItem.publisher(for: \.duration)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] duration in
                if duration.isNumeric {
                    self?.duration = duration.seconds
                }
            }
            .store(in: &cancellables)

        // Buffering
        playerItem.publisher(for: \.isPlaybackBufferEmpty)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEmpty in
                self?.isBuffering = isEmpty
            }
            .store(in: &cancellables)

        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                switch status {
                case .playing:
                    self?.isPlaying = true
                    self?.isBuffering = false
                case .paused:
                    self?.isPlaying = false
                case .waitingToPlayAtSpecifiedRate:
                    self?.isPlaying = false
                    self?.isBuffering = true
                @unknown default:
                    self?.isPlaying = false
                }
            }
            .store(in: &cancellables)

        // Status
        playerItem.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                switch status {
                case .failed:
                    if let error = playerItem.error {
                        print("AVPlayerController: playerItem failed: \(error)")
                    }
                    if let errorLog = playerItem.errorLog() {
                        print("AVPlayerController: errorLog = \(errorLog.events)")
                    }
                    self?.error = playerItem.error
                case .readyToPlay:
                    self?.applyInitialSeekIfNeeded()
                    self?.isBuffering = false
                default:
                    break
                }
            }
            .store(in: &cancellables)

        // Playback ended
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: playerItem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isPlaying = false
                self?.handlePlaybackEnded()
            }
            .store(in: &cancellables)
    }

    // MARK: - Playback Position

    private func initialPosition(for url: URL, resumePosition: TimeInterval?) -> TimeInterval? {
        if let resumePosition, resumePosition > 1 {
            return resumePosition
        }

        guard settings.playResume else { return nil }
        return getLastPosition(for: url)
    }

    private func getLastPosition(for url: URL) -> TimeInterval? {
        let key = "lastPosition_\(url.absoluteString.hashValue)"
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }

        let position = UserDefaults.standard.double(forKey: key)
        return position > 1 ? position : nil
    }

    private func applyInitialSeekIfNeeded() {
        guard !didApplyInitialSeek,
              let initialSeekTime,
              initialSeekTime > 1 else {
            return
        }

        didApplyInitialSeek = true
        seek(to: initialSeekTime)
    }

    private func savePosition(url: URL, position: TimeInterval) {
        let key = "lastPosition_\(url.absoluteString.hashValue)"
        UserDefaults.standard.set(position, forKey: key)
    }

    private func clearPosition(for url: URL) {
        let key = "lastPosition_\(url.absoluteString.hashValue)"
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func inferredMIMEType(for url: URL) -> String? {
        let pathExtension = url.pathExtension.lowercased()
        if pathExtension == "m3u8" {
            return "application/vnd.apple.mpegurl"
        }
        if pathExtension == "mp4" || pathExtension == "m4v" || pathExtension == "mov" {
            return "video/mp4"
        }

        let absolute = url.absoluteString.lowercased()
        let host = url.host?.lowercased() ?? ""
        let knownVideoHosts = [
            "toutiao",
            "byte",
            "ixigua",
            "bilivideo",
            "mgtv",
            "alicdn",
            "akamaized"
        ]
        let knownVideoPaths = ["/video/", "/tos/", "/vod/"]

        if knownVideoHosts.contains(where: { host.contains($0) }) ||
            knownVideoPaths.contains(where: { absolute.contains($0) }) {
            return "video/mp4"
        }

        return nil
    }

    // MARK: - End Handling

    private func handlePlaybackEnded() {
        // Clear position for next episode
        if let url = currentSource?.url {
            clearPosition(for: url)
        }

        // Auto-play next if enabled
        if settings.autoPlayNext {
            NotificationCenter.default.post(name: .playerDidFinishEpisode, object: nil)
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        cancellables.removeAll()

        player?.pause()
        player = nil
        playerItem = nil
        pendingSeekTime = nil
        initialSeekTime = nil
        didApplyInitialSeek = false

        isPlaying = false
        currentTime = 0
        duration = 0
        isBuffering = false
        error = nil
    }

    deinit {
        // Cleanup on deinit
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let playerDidFinishEpisode = Notification.Name("playerDidFinishEpisode")
}

// MARK: - Player Error

enum PlayerError: LocalizedError {
    case invalidURL
    case loadFailed
    case playbackFailed
    case missingEpisodeURL
    case serverProxyDisabled
    case playbackTimeout

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的视频地址"
        case .loadFailed:
            return "视频加载失败"
        case .playbackFailed:
            return "视频播放失败"
        case .missingEpisodeURL:
            return "当前章节没有插件播放页地址。请从搜索里的插件结果进入详情页，或先为该番剧匹配可播放源。"
        case .serverProxyDisabled:
            return "服务器代理未启用。请在设置中开启服务器代理。"
        case .playbackTimeout:
            return "当前线路启动超时，暂时无法播放。"
        }
    }
}
