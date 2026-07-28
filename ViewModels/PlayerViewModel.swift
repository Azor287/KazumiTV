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
    @Published var danmakuMassive = false
    @Published var danmakuArea: Double = 1.0
    @Published var danmakuDuration: TimeInterval = 8.0
    @Published var danmakuLoading = false
    @Published var danmakuStatusMessage: String?

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
    private let videoResolveTimeoutNanoseconds: UInt64 = 20_000_000_000

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
        danmakuMassive = settings.danmakuMassive
        danmakuArea = settings.danmakuArea
        danmakuDuration = settings.danmakuDuration
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
        startDanmakuLoading(for: bangumi, episode: episode, generation: generation)

        // Always resolve video source, regardless of episode list
        await resolveVideoSource(for: episode, resumePosition: resumePosition, generation: generation)
    }

    func loadVideo(source: VideoSource, danmakuItems: [DanmakuItem] = [], resumePosition: TimeInterval? = nil) {
        _ = beginLoadGeneration()
        danmakuLoadingTask?.cancel()
        danmakuLoading = false
        danmakuStatusMessage = nil
        loadResolvedVideo(source: source, danmakuItems: danmakuItems, resumePosition: resumePosition)
    }

    private func loadResolvedVideo(source: VideoSource, danmakuItems: [DanmakuItem]? = nil, resumePosition: TimeInterval? = nil) {
        currentSource = source
        if let danmakuItems {
            self.danmakuItems = danmakuItems
        }
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
        print("PlayerViewModel.resolveVideoSource: episode.pageURL = \(URLLogSanitizer.redacted(episode.pageURL))")
        print("PlayerViewModel.resolveVideoSource: episode.pluginName = \(episode.pluginName ?? "nil")")
        isBuffering = true
        error = nil

        // 如果 episode 有 pageURL，使用它来解析视频
        if let pageURL = episode.pageURL, !pageURL.isEmpty {
            print("PlayerViewModel.resolveVideoSource: 使用 pageURL 解析: \(URLLogSanitizer.redacted(pageURL))")
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
        print(
            "PlayerViewModel.resolveWithPageURL: 开始本机解析 pageURL: "
                + "\(URLLogSanitizer.redacted(pageURL)), pluginName: \(pluginName ?? "nil")"
        )

        // 优先使用 tvOS 原生解析；外部解析服务只作为显式后备。
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
            let videoSource = try await resolveVideoURLWithTimeout(
                resolver: resolver,
                pageURL: pageURL,
                plugin: plugin
            )
            guard isCurrentLoad(generation) else { return }
            print(
                "PlayerViewModel.resolveWithPageURL: 本机解析成功，videoSource.url = "
                    + URLLogSanitizer.redacted(videoSource.url)
            )
            loadResolvedVideo(source: videoSource, resumePosition: resumePosition)
        } catch {
            guard isCurrentLoad(generation) else { return }
            print("PlayerViewModel.resolveWithPageURL: 视频解析失败: \(error)")
            isBuffering = false
            self.error = error
        }
    }

    private func resolveVideoURLWithTimeout(
        resolver: VideoSourceResolver,
        pageURL: String,
        plugin: PluginRule
    ) async throws -> VideoSource {
        let timeoutNanoseconds = SettingsRepository.shared.privateWebResolverEnabled
            ? 36_000_000_000
            : videoResolveTimeoutNanoseconds
        return try await withThrowingTaskGroup(of: VideoSource.self) { group in
            group.addTask {
                try await resolver.resolveVideoURL(pageURL: pageURL, plugin: plugin)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw PlayerError.playbackTimeout
            }
            defer { group.cancelAll() }

            guard let source = try await group.next() else {
                throw CancellationError()
            }
            return source
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
        startDanmakuLoading(
            bangumiId: bangumiId,
            episodeNumber: episodeNumber,
            generation: loadGeneration
        )
    }

    func reloadDanmakuForCurrentEpisode() {
        guard let currentBangumi, let currentEpisode else { return }
        startDanmakuLoading(for: currentBangumi, episode: currentEpisode, generation: loadGeneration)
    }

    private func startDanmakuLoading(for bangumi: Bangumi, episode: Episode, generation: UInt64) {
        startDanmakuLoading(
            bangumiId: bangumi.id,
            episodeNumber: resolvedDanmakuEpisodeNumber(for: episode),
            generation: generation
        )
    }

    private func startDanmakuLoading(bangumiId: Int, episodeNumber: Int, generation: UInt64) {
        danmakuLoadingTask?.cancel()
        danmakuItems = []
        danmakuStatusMessage = nil

        guard bangumiId > 0, episodeNumber > 0 else {
            danmakuLoading = false
            danmakuStatusMessage = "当前分集无法匹配弹幕"
            return
        }

        danmakuLoading = true
        let shouldDeduplicate = settings.danmakuDeduplication
        let danmakuAPI = self.danmakuAPI

        danmakuLoadingTask = Task {
            do {
                let loadedItems = try await danmakuAPI.getCommentsByBgmId(
                    bgmBangumiId: bangumiId,
                    episode: episodeNumber
                )
                let items = shouldDeduplicate
                    ? loadedItems.removingNearbyDuplicates()
                    : loadedItems.sorted { $0.time < $1.time }

                await MainActor.run {
                    guard self.isCurrentLoad(generation), !Task.isCancelled else { return }
                    self.danmakuItems = items
                    self.danmakuLoading = false
                    self.danmakuStatusMessage = items.isEmpty ? "未找到弹幕" : nil
                }
            } catch {
                await MainActor.run {
                    guard self.isCurrentLoad(generation), !Task.isCancelled else { return }
                    self.danmakuItems = []
                    self.danmakuLoading = false
                    self.danmakuStatusMessage = error.localizedDescription
                    print("Failed to load danmaku: \(error)")
                }
            }
        }
    }

    private func resolvedDanmakuEpisodeNumber(for episode: Episode) -> Int {
        if episode.episodeNumber > 0 {
            return episode.episodeNumber
        }

        return extractEpisodeNumber(from: episode.displayName)
    }

    private func extractEpisodeNumber(from text: String) -> Int {
        let pattern = #"第?\s*(\d+)\s*[话話集]?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return 0
        }

        return Int(text[range]) ?? 0
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

    func toggleDanmaku() {
        danmakuEnabled.toggle()
        settings.danmakuEnabledByDefault = danmakuEnabled

        if danmakuEnabled && danmakuItems.isEmpty && !danmakuLoading {
            reloadDanmakuForCurrentEpisode()
        }
    }

    func beginInteractiveSeek() {
        playerController.beginInteractiveSeek()
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
        settings.danmakuMassive = danmakuMassive
        settings.danmakuArea = danmakuArea
        settings.danmakuDuration = danmakuDuration
    }

    // MARK: - Cleanup

    func cleanup() {
        _ = beginLoadGeneration()
        controlsTimer?.invalidate()
        danmakuLoadingTask?.cancel()
        danmakuLoading = false
        danmakuStatusMessage = nil
        danmakuItems = []
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
