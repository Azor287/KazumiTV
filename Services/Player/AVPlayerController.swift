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
    private var seekGeneration: UInt64 = 0
    private var resumeGeneration: UInt64 = 0
    private var shouldResumePlaybackAfterSeek = false
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

        let playbackSource: VideoSource
        do {
            playbackSource = try LocalHLSProxy.shared.proxiedSource(for: source)
            if playbackSource.url != source.url {
                if playbackSource.url.host == "127.0.0.1" || playbackSource.url.host == "localhost" {
                    print("AVPlayerController.loadVideo: 使用真机本地 loopback 播放URL: \(URLLogSanitizer.redacted(playbackSource.url))")
                } else {
                    print("AVPlayerController.loadVideo: 使用直连播放URL: \(URLLogSanitizer.redacted(playbackSource.url))")
                }
            }
        } catch {
            print("AVPlayerController.loadVideo: 本地播放代理准备失败: \(error)")
            self.error = error
            isBuffering = false
            return
        }

        var options: [String: Any] = [:]
        var assetHeaders = playbackSource.headers
        if let referer = playbackSource.referer, !referer.isEmpty {
            assetHeaders["Referer"] = referer
        }
        if !assetHeaders.isEmpty {
            options["AVURLAssetHTTPHeaderFieldsKey"] = assetHeaders
        }

        if let mimeType = inferredMIMEType(for: playbackSource.url) ?? inferredMIMEType(for: source.url) {
            options["AVURLAssetOutOfBandMIMETypeKey"] = mimeType
            print("AVPlayerController.loadVideo: 使用 MIME type \(mimeType), url = \(URLLogSanitizer.redacted(playbackSource.url))")
        }

        let asset = AVURLAsset(url: playbackSource.url, options: options)
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
        guard pendingSeekTime == nil else {
            shouldResumePlaybackAfterSeek = true
            isBuffering = true
            return
        }

        player?.play()
        player?.rate = playbackRate
    }

    func pause() {
        shouldResumePlaybackAfterSeek = false
        cancelPendingResume()
        player?.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        if pendingSeekTime != nil {
            shouldResumePlaybackAfterSeek ? pause() : play()
            return
        }

        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func beginInteractiveSeek() {
        _ = prepareForSeek()
    }

    func seek(to time: TimeInterval, tolerance: TimeInterval = 0.5) {
        let upperBound = duration > 0 ? duration : time
        let targetTime = max(0, min(time, upperBound))
        let shouldResumePlayback = prepareForSeek()
        seekGeneration &+= 1
        let currentSeekGeneration = seekGeneration
        pendingSeekTime = targetTime
        currentTime = targetTime

        let cmTime = CMTime(seconds: targetTime, preferredTimescale: 600)
        let toleranceTime = CMTime(seconds: max(0, tolerance), preferredTimescale: 600)
        playerItem?.cancelPendingSeeks()
        player?.seek(to: cmTime, toleranceBefore: toleranceTime, toleranceAfter: toleranceTime) { [weak self] finished in
            Task { @MainActor in
                guard let self, self.seekGeneration == currentSeekGeneration else { return }
                if finished {
                    self.currentTime = targetTime
                }
                self.pendingSeekTime = nil

                if finished, shouldResumePlayback, self.shouldResumePlaybackAfterSeek {
                    self.resumePlaybackWhenReady(for: currentSeekGeneration)
                } else if !self.shouldResumePlaybackAfterSeek {
                    self.isBuffering = self.playerItem?.isPlaybackBufferEmpty ?? false
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

    private var isPlaybackActive: Bool {
        isPlaying ||
        player?.timeControlStatus == .playing ||
        player?.timeControlStatus == .waitingToPlayAtSpecifiedRate
    }

    private func prepareForSeek() -> Bool {
        cancelPendingResume()

        let shouldResumePlayback = shouldResumePlaybackAfterSeek || isPlaybackActive
        shouldResumePlaybackAfterSeek = shouldResumePlayback

        if shouldResumePlayback {
            player?.pause()
            isPlaying = false
            isBuffering = true
        }

        return shouldResumePlayback
    }

    private func resumePlaybackWhenReady(for seekGeneration: UInt64) {
        guard player != nil else {
            shouldResumePlaybackAfterSeek = false
            isBuffering = false
            return
        }

        resumeGeneration &+= 1
        let currentResumeGeneration = resumeGeneration
        resumePlaybackIfPending(
            seekGeneration: seekGeneration,
            resumeGeneration: currentResumeGeneration
        )
    }

    private func resumePlaybackIfPending(
        seekGeneration expectedSeekGeneration: UInt64? = nil,
        resumeGeneration expectedResumeGeneration: UInt64? = nil
    ) {
        guard shouldResumePlaybackAfterSeek,
              pendingSeekTime == nil,
              expectedSeekGeneration.map({ $0 == seekGeneration }) ?? true,
              expectedResumeGeneration.map({ $0 == resumeGeneration }) ?? true else {
            return
        }

        shouldResumePlaybackAfterSeek = false
        player?.play()
        player?.rate = playbackRate
    }

    private func cancelPendingResume() {
        resumeGeneration &+= 1
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
                guard self?.shouldResumePlaybackAfterSeek != true else {
                    self?.isBuffering = true
                    return
                }
                self?.isBuffering = isEmpty
            }
            .store(in: &cancellables)

        playerItem.publisher(for: \.isPlaybackLikelyToKeepUp)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLikelyToKeepUp in
                guard isLikelyToKeepUp else { return }
                self?.resumePlaybackIfPending()
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
                    self?.error = self?.normalizedPlaybackError(playerItem.error) ?? PlayerError.playbackFailed
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

    private func normalizedPlaybackError(_ error: Error?) -> Error {
        guard let error else {
            return PlayerError.playbackFailed
        }

        let description = error.localizedDescription.lowercased()
        if description.contains("resource unavailable") {
            return PlayerError.resourceUnavailable
        }

        return error
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
        let absolute = url.absoluteString.lowercased()
        if pathExtension == "m3u8" || absolute.contains("m3u8") || url.path.lowercased().contains("/playlist/") {
            return "application/vnd.apple.mpegurl"
        }
        if pathExtension == "mp4" || pathExtension == "m4v" || pathExtension == "mov" {
            return "video/mp4"
        }

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

        shouldResumePlaybackAfterSeek = false
        cancelPendingResume()
        player?.pause()
        player = nil
        playerItem = nil
        pendingSeekTime = nil
        seekGeneration &+= 1
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
    case playbackTimeout
    case resourceUnavailable

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
        case .playbackTimeout:
            return "当前线路启动超时，暂时无法播放。"
        case .resourceUnavailable:
            return "当前线路资源不可用或地区受限，正在尝试其他线路。"
        }
    }
}
