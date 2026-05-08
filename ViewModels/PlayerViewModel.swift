//
//  PlayerViewModel.swift
//  KazumiTV
//
//  Video Player ViewModel
//

import Foundation
import Combine

@MainActor
class PlayerViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isBuffering = true
    @Published var playbackRate: Float = 1.0
    @Published var volume: Float = 1.0
    @Published var error: Error?

    // Danmaku
    @Published var danmakuEnabled = true
    @Published var danmakuOpacity: Double = 1.0
    @Published var danmakuFontSize: CGFloat = 18
    @Published var danmakuShowTop = true
    @Published var danmakuShowScroll = true
    @Published var danmakuShowBottom = true

    // Player state
    @Published var showControls = true
    @Published var showDanmakuSettings = false
    @Published var isFullScreen = false

    // Current content
    @Published var currentBangumi: Bangumi?
    @Published var currentEpisode: Episode?
    @Published var currentSource: VideoSource?
    @Published var danmakuItems: [DanmakuItem] = []
    @Published var availableSources: [VideoSource] = []
    @Published var selectedSourceIndex = 0

    // MARK: - Services
    let playerController = AVPlayerController()
    private let danmakuAPI = DanDanPlayAPI.shared
    private let settings = SettingsRepository.shared

    private var cancellables = Set<AnyCancellable>()
    private var controlsTimer: Timer?
    private var danmakuLoadingTask: Task<Void, Never>?
    private var loadGeneration: UInt64 = 0

    // MARK: - Init

    init() {
        loadSettings()
        setupBindings()
    }

    private func loadSettings() {
        danmakuEnabled = settings.danmakuEnabledByDefault
        danmakuOpacity = settings.danmakuOpacity
        danmakuFontSize = settings.danmakuFontSize
        danmakuShowTop = settings.danmakuTop
        danmakuShowScroll = settings.danmakuScroll
        danmakuShowBottom = settings.danmakuBottom
    }

    private func setupBindings() {
        playerController.$isPlaying
            .receive(on: DispatchQueue.main)
            .assign(to: &$isPlaying)

        playerController.$currentTime
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentTime)

        playerController.$duration
            .receive(on: DispatchQueue.main)
            .assign(to: &$duration)

        playerController.$isBuffering
            .receive(on: DispatchQueue.main)
            .assign(to: &$isBuffering)

        playerController.$error
            .receive(on: DispatchQueue.main)
            .assign(to: &$error)
    }

    // MARK: - Load Video

    func loadVideo(bangumi: Bangumi, episode: Episode, resumePosition: TimeInterval? = nil) async {
        let generation = beginLoadGeneration()
        print("PlayerViewModel.loadVideo called for bangumi: \(bangumi.displayName), episode: \(episode.displayName)")
        currentBangumi = bangumi
        currentEpisode = episode

        // Always resolve video source, regardless of episode list
        await resolveVideoSource(for: episode, resumePosition: resumePosition, generation: generation)
    }

    func loadVideo(source: VideoSource, danmakuItems: [DanmakuItem] = [], resumePosition: TimeInterval? = nil) {
        _ = beginLoadGeneration()
        loadResolvedVideo(source: source, danmakuItems: danmakuItems, resumePosition: resumePosition)
    }

    private func loadResolvedVideo(source: VideoSource, danmakuItems: [DanmakuItem] = [], resumePosition: TimeInterval? = nil) {
        currentSource = source
        self.danmakuItems = danmakuItems
        selectedSourceIndex = 0

        playerController.loadVideo(source: source, resumePosition: resumePosition)
        play()
    }

    func loadVideo(url: URL) {
        let source = VideoSource(url: url, quality: "默认", pluginName: "")
        loadVideo(source: source)
    }

    func forcePlaybackTimeout() {
        playerController.cleanup()
        isBuffering = false
        error = PlayerError.playbackTimeout
    }

    // MARK: - Video Resolution

    private func resolveVideoSource(for episode: Episode, resumePosition: TimeInterval? = nil, generation: UInt64) async {
        guard isCurrentLoad(generation) else { return }
        print("PlayerViewModel.resolveVideoSource: 开始解析视频源")
        print("PlayerViewModel.resolveVideoSource: episode.pageURL = \(episode.pageURL ?? "nil")")
        print("PlayerViewModel.resolveVideoSource: episode.pluginName = \(episode.pluginName ?? "nil")")
        isBuffering = true
        error = nil

        // 如果 episode 有 pageURL，使用它来解析视频
        if let pageURL = episode.pageURL, !pageURL.isEmpty {
            print("PlayerViewModel.resolveVideoSource: 使用 pageURL 解析: \(pageURL)")
            await resolveWithPageURL(pageURL, pluginName: episode.pluginName, resumePosition: resumePosition, generation: generation)
            return
        }

        guard isCurrentLoad(generation) else { return }
        print("PlayerViewModel.resolveVideoSource: 没有 pageURL，无法解析视频")
        isBuffering = false
        error = PlayerError.missingEpisodeURL
    }

    private func resolveWithPageURL(_ pageURL: String, pluginName: String?, resumePosition: TimeInterval? = nil, generation: UInt64) async {
        guard isCurrentLoad(generation) else { return }
        print("PlayerViewModel.resolveWithPageURL: 开始解析 pageURL: \(pageURL), pluginName: \(pluginName ?? "nil")")
        let settings = SettingsRepository.shared
        print("PlayerViewModel.resolveWithPageURL: serverProxyEnabled = \(settings.serverProxyEnabled)")
        print("PlayerViewModel.resolveWithPageURL: serverProxyURL = \(settings.serverProxyURL)")

        guard settings.serverProxyEnabled else {
            guard isCurrentLoad(generation) else { return }
            print("PlayerViewModel.resolveWithPageURL: 服务器代理未启用")
            isBuffering = false
            error = PlayerError.serverProxyDisabled
            return
        }

        // 使用服务器代理获取视频
        do {
            let resolver = VideoSourceResolver.shared
            print("PlayerViewModel.resolveWithPageURL: 获取 VideoSourceResolver")

            // 获取插件
            let plugin: PluginRule
            if let name = pluginName {
                print("PlayerViewModel.resolveWithPageURL: 获取插件: \(name)")
                plugin = try await getPlugin(name: name)
            } else {
                // 默认使用 AGE 插件
                print("PlayerViewModel.resolveWithPageURL: 使用默认插件: AGE")
                plugin = try await getPlugin(name: "AGE")
            }
            guard isCurrentLoad(generation) else { return }

            print("PlayerViewModel.resolveWithPageURL: 调用 resolver.resolveVideoURL")
            let videoSource = try await resolver.resolveVideoURL(pageURL: pageURL, plugin: plugin)
            guard isCurrentLoad(generation) else { return }
            print("PlayerViewModel.resolveWithPageURL: 解析成功，videoSource.url = \(videoSource.url)")
            loadResolvedVideo(source: videoSource, resumePosition: resumePosition)
        } catch {
            guard isCurrentLoad(generation) else { return }
            print("PlayerViewModel.resolveWithPageURL: 视频解析失败: \(error)")
            isBuffering = false
            self.error = error
        }
    }

    private func beginLoadGeneration() -> UInt64 {
        loadGeneration &+= 1
        return loadGeneration
    }

    private func isCurrentLoad(_ generation: UInt64) -> Bool {
        generation == loadGeneration && !Task.isCancelled
    }

    private func getPlugin(name: String) async throws -> PluginRule {
        let pluginManager = PluginManager.shared
        try await pluginManager.loadPlugins()
        guard let plugin = await pluginManager.getPlugin(name: name) else {
            throw PluginError.pluginNotFound(name)
        }
        return plugin
    }

    // MARK: - Danmaku Loading

    func loadDanmaku(bangumiId: Int, episodeNumber: Int) async {
        danmakuLoadingTask?.cancel()

        danmakuLoadingTask = Task {
            do {
                let items = try await danmakuAPI.getCommentsByBgmId(bgmBangumiId: bangumiId, episode: episodeNumber)
                if !Task.isCancelled {
                    self.danmakuItems = items
                }
            } catch {
                if !Task.isCancelled {
                    print("Failed to load danmaku: \(error)")
                }
            }
        }
    }

    // MARK: - Playback Controls

    func play() {
        playerController.play()
        // Don't auto-hide controls on tvOS
        showControls = true
    }

    func pause() {
        playerController.pause()
        showControls = true
        controlsTimer?.invalidate()
    }

    func togglePlayPause() {
        playerController.togglePlayPause()
    }

    func seek(to time: TimeInterval) {
        playerController.seek(to: time)
    }

    func seekForward() {
        playerController.seekForward()
    }

    func seekBackward() {
        playerController.seekBackward()
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        playerController.setRate(rate)
    }

    func setVolume(_ volume: Float) {
        self.volume = volume
        playerController.setVolume(volume)
    }

    // MARK: - Controls Visibility

    func toggleControls() {
        showControls.toggle()
    }

    private func startControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                if self?.isPlaying == true {
                    self?.showControls = false
                }
            }
        }
    }

    // MARK: - Source Selection

    func selectSource(index: Int) {
        guard index < availableSources.count else { return }
        selectedSourceIndex = index

        let source = availableSources[index]
        playerController.loadVideo(source: source)
    }

    // MARK: - Settings

    func saveDanmakuSettings() {
        settings.danmakuEnabledByDefault = danmakuEnabled
        settings.danmakuOpacity = danmakuOpacity
        settings.danmakuFontSize = danmakuFontSize
        settings.danmakuTop = danmakuShowTop
        settings.danmakuScroll = danmakuShowScroll
        settings.danmakuBottom = danmakuShowBottom
    }

    // MARK: - Cleanup

    func cleanup() {
        _ = beginLoadGeneration()
        controlsTimer?.invalidate()
        danmakuLoadingTask?.cancel()
        currentSource = nil
        playerController.cleanup()
    }

    // MARK: - Time Formatting

    var currentTimeText: String {
        formatTime(currentTime)
    }

    var durationText: String {
        formatTime(duration)
    }

    var remainingTimeText: String {
        formatTime(duration - currentTime)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
