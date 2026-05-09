//
//  PlayerView.swift
//  KazumiTV
//
//  Video Player View with AVPlayer and Danmaku overlay
//

import SwiftUI
import AVKit
import UIKit

struct PlayerView: View {
    let bangumi: Bangumi
    let episode: Episode
    let playbackSession: PlaybackSession?

    @ObservedObject private var router = Router.shared
    @StateObject private var viewModel = PlayerViewModel()
    @State private var focusedControl: PlayerControl?
    @State private var activeEpisode: Episode
    @State private var selectedRoadID: String?
    @State private var activePlaybackSession: PlaybackSession?
    @State private var showingPlaylist = false
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var seekFeedback: SeekFeedback?
    @State private var seekFeedbackTask: Task<Void, Never>?
    @State private var directionalSeekCommitTask: Task<Void, Never>?
    @State private var committedSeekDisplayTask: Task<Void, Never>?
    @State private var scrubPreviewTime: TimeInterval?
    @State private var committedSeekDisplayTime: TimeInterval?
    @State private var lastControlMoveAt = Date.distantPast
    @State private var playlistFocus: PlaylistFocus?
    @State private var recordedPlaybackSuccess = false
    @State private var recordedPlaybackFailure = false
    @State private var episodeLoadTask: Task<Void, Never>?
    @State private var playbackStartupTask: Task<Void, Never>?
    @State private var lastHistorySaveTime: TimeInterval = 0
    @State private var pendingResumePosition: TimeInterval?
    @State private var pendingResumeEpisodeNumber: Int?
    @State private var failedPlaybackRoadKeys = Set<String>()
    @State private var failedPlaybackSourceKeys = Set<String>()
    private let directionalSeekStep: TimeInterval = 5
    private let directionalSeekCommitDelay: UInt64 = 80_000_000

    init(bangumi: Bangumi, episode: Episode, playbackSession: PlaybackSession? = nil) {
        self.bangumi = bangumi
        self.episode = episode
        self.playbackSession = playbackSession
        _activeEpisode = State(initialValue: episode)
        _selectedRoadID = State(initialValue: playbackSession?.selectedRoadID)
        _activePlaybackSession = State(initialValue: playbackSession)
        _pendingResumePosition = State(initialValue: playbackSession?.resumePosition)
        _pendingResumeEpisodeNumber = State(
            initialValue: playbackSession?.resumePosition == nil
                ? nil
                : playbackSession?.selectedEpisode?.episodeNumber ?? episode.episodeNumber
        )
    }

    init(session: PlaybackSession) {
        let selectedEpisode = session.selectedEpisode ?? Episode.sample
        self.init(bangumi: session.bangumi, episode: selectedEpisode, playbackSession: session)
    }

    private var activeRoad: PlaybackRoad? {
        guard let activePlaybackSession else { return nil }
        if let selectedRoadID,
           let road = activePlaybackSession.roads.first(where: { $0.id == selectedRoadID }) {
            return road
        }
        return activePlaybackSession.selectedRoad
    }

    private var activeEpisodes: [Episode] {
        activeRoad?.episodes ?? []
    }

    private var hasPlaylist: Bool {
        !activeEpisodes.isEmpty
    }

    private var playlistColumnCount: Int {
        3
    }

    private var shouldShowLoading: Bool {
        viewModel.error == nil && (viewModel.playerController.player == nil || viewModel.isBuffering)
    }

    private var shouldShowControls: Bool {
        viewModel.showControls &&
        viewModel.error == nil &&
        viewModel.playerController.player != nil
    }

    private var progress: Double {
        guard viewModel.duration > 0 else { return 0 }
        let displayTime = playerDisplayTime
        return min(max(displayTime / viewModel.duration, 0), 1)
    }

    private var displayedCurrentTimeText: String {
        formatPlayerTime(playerDisplayTime)
    }

    private var playerDisplayTime: TimeInterval {
        scrubPreviewTime ?? committedSeekDisplayTime ?? viewModel.currentTime
    }

    private var shouldEnableRemoteScrub: Bool {
        shouldShowControls &&
        !showingPlaylist &&
        viewModel.duration > 0 &&
        viewModel.playerController.player != nil
    }

    var body: some View {
        ZStack {
            if let player = viewModel.playerController.player {
                VideoPlayerLayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            } else {
                Color.black
                    .ignoresSafeArea()
            }

            if shouldShowLoading {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            }

            DanmakuOverlayView(
                danmakus: viewModel.danmakuItems,
                currentTime: viewModel.currentTime,
                isEnabled: viewModel.danmakuEnabled,
                fontSize: viewModel.danmakuFontSize,
                opacity: viewModel.danmakuOpacity,
                showTop: viewModel.danmakuShowTop,
                showScroll: viewModel.danmakuShowScroll,
                showBottom: viewModel.danmakuShowBottom
            )
            .ignoresSafeArea()

            if let seekFeedback, !shouldShowLoading {
                seekFeedbackOverlay(seekFeedback)
            }

            if shouldShowControls {
                controlsOverlay
                    .transition(.opacity)
            }

            RemoteScrubGestureLayer(
                isEnabled: shouldEnableRemoteScrub,
                currentTime: viewModel.currentTime,
                duration: viewModel.duration,
                onBegin: beginRemoteScrub,
                onChange: updateRemoteScrub,
                onEnd: commitRemoteScrub
            )
            .ignoresSafeArea()
            .allowsHitTesting(shouldEnableRemoteScrub)

            if showingPlaylist, let activePlaybackSession {
                playlistOverlay(session: activePlaybackSession)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if let error = viewModel.error {
                errorOverlay(error)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .focusable()
        .onTapGesture {
            handleSelect()
        }
        .onMoveCommand(perform: handleMoveCommand)
        .onPlayPauseCommand {
            handlePlayPauseCommand()
        }
        .onExitCommand {
            if showingPlaylist {
                closePlaylist()
            } else if viewModel.error != nil {
                router.pop()
            } else if viewModel.showControls {
                hideControls()
            } else {
                router.pop()
            }
        }
        .onChange(of: viewModel.isPlaying) { _, isPlaying in
            if isPlaying {
                recordPlaybackSuccessIfNeeded()
                scheduleControlsAutoHide()
            } else if !viewModel.isBuffering {
                showControls(autoHide: false)
            }
        }
        .onChange(of: viewModel.isBuffering) { _, isBuffering in
            if !isBuffering && viewModel.error == nil && viewModel.showControls {
                scheduleControlsAutoHide()
            }
        }
        .onChange(of: viewModel.duration) { _, _ in
            guard viewModel.showControls, focusedControl == nil, viewModel.error == nil else { return }
            focusedControl = defaultFocusedControl
        }
        .onChange(of: viewModel.currentTime) { _, currentTime in
            clearCommittedSeekDisplayIfReached(currentTime)
            savePlaybackProgressIfNeeded(currentTime: currentTime)
        }
        .onChange(of: viewModel.error != nil) { _, hasError in
            if hasError {
                recordPlaybackFailureIfNeeded()
                cancelControlsAutoHide()
            }
        }
        .onAppear {
            print("PlayerView.onAppear - bangumi: \(bangumi.displayName), episode: \(activeEpisode.displayName)")
            showControls(autoHide: false)
            startPlaybackTask {
                await loadActiveEpisode()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .playerDidFinishEpisode)) { _ in
            savePlaybackProgressIfNeeded(force: true)
            startPlaybackTask {
                await playAdjacentEpisode(1)
            }
        }
        .onDisappear {
            savePlaybackProgressIfNeeded(force: true)
            episodeLoadTask?.cancel()
            hideControlsTask?.cancel()
            seekFeedbackTask?.cancel()
            cancelDirectionalSeekPreview()
            clearCommittedSeekDisplay()
            playbackStartupTask?.cancel()
            viewModel.cleanup()
        }
    }

    private var controlsOverlay: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.54),
                    Color.black.opacity(0.92)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity, maxHeight: 430)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Text(bangumi.displayName)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Image(systemName: "pause.fill")
                            .font(.headline.weight(.bold))
                            .foregroundColor(.white.opacity(0.82))
                            .opacity(viewModel.isPlaying ? 0 : 1)
                            .accessibilityHidden(viewModel.isPlaying)

                        Spacer(minLength: 0)
                    }

                    Text(activeEpisode.displayName)
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.72))
                        .lineLimit(1)
                }

                HStack(alignment: .center, spacing: 18) {
                    playerTimeText(
                        displayedCurrentTimeText,
                        color: scrubPreviewTime == nil ? .white : .kzPrimary,
                        alignment: .leading
                    )

                    PlayerProgressBar(
                        progress: progress,
                        isScrubbing: scrubPreviewTime != nil,
                        isFocused: focusedControl == .progress
                    )
                    .frame(height: 34)
                    .layoutPriority(1)
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityLabel("播放进度")
                    .accessibilityValue("\(displayedCurrentTimeText) / \(viewModel.durationText)")
                    .onMoveCommand { direction in
                        handleControlMoveCommand(direction)
                    }

                    playerTimeText(
                        viewModel.durationText,
                        color: .white.opacity(0.86),
                        alignment: .trailing
                    )
                }

                HStack(alignment: .center, spacing: 14) {
                    if hasPlaylist {
                        playerControlButton(control: .nextEpisode, icon: "forward.end.fill", size: 26) {
                            startPlaybackTask {
                                await playAdjacentEpisode(1)
                            }
                        }
                    }

                    Spacer(minLength: 36)

                    if activePlaybackSession != nil {
                        playerControlButton(control: .playlist, icon: "list.bullet.rectangle", title: "选集", size: 27) {
                            openPlaylist()
                        }
                    }
                }
                .frame(height: 74)
            }
            .padding(.horizontal, 72)
            .padding(.bottom, 58)
            .focusSection()
        }
        .animation(.easeInOut(duration: 0.18), value: viewModel.showControls)
    }

    private func playerTimeText(_ text: String, color: Color, alignment: Alignment) -> some View {
        Text(text)
            .font(.callout.monospacedDigit())
            .fontWeight(.semibold)
            .foregroundColor(color)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .allowsTightening(true)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: 104, alignment: alignment)
    }

    private func playerControlButton(
        control: PlayerControl,
        icon: String,
        title: String? = nil,
        size: CGFloat = 44,
        isPrimary: Bool = false,
        action: @escaping () -> Void
        ) -> some View {
        Button(action: action) {
            HStack(spacing: title == nil ? 0 : 10) {
                Image(systemName: icon)
                    .font(.system(size: size, weight: .semibold))

                if let title {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, title == nil ? 0 : 18)
            .frame(
                minWidth: title == nil ? (isPrimary ? 84 : 74) : 132,
                minHeight: isPrimary ? 68 : 62
            )
        }
        .buttonStyle(PlayerTransportButtonStyle(
            isFocused: focusedControl == control,
            isPrimary: isPrimary
        ))
        .onMoveCommand { direction in
            handleControlMoveCommand(direction)
        }
    }

    private func seekFeedbackOverlay(_ feedback: SeekFeedback) -> some View {
        Image(systemName: feedback.icon)
            .font(.system(size: 58, weight: .semibold))
            .frame(width: 116, height: 116)
        .foregroundColor(.white)
        .background(Color.black.opacity(0.54))
        .clipShape(Circle())
        .transition(.scale.combined(with: .opacity))
    }

    private func errorOverlay(_ error: Error) -> some View {
        VStack(spacing: 22) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundColor(.kzPrimary)

            VStack(spacing: 8) {
                Text("无法播放")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text(error.localizedDescription)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
            }

            HStack(spacing: 12) {
                Image(systemName: "play.fill")
                    .font(.headline.weight(.semibold))

                Text("按播放键重试")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white.opacity(0.86))
        }
        .frame(width: 760)
        .padding(.vertical, 44)
        .padding(.horizontal, 54)
        .background(Color.black.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func playlistOverlay(session: PlaybackSession) -> some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.48)
                .ignoresSafeArea()
                .onTapGesture {
                    closePlaylist()
                }

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("选集")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        Text("\(session.source.pluginName) · \(session.source.displayName)")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.68))
                            .lineLimit(2)
                    }

                    Spacer()

                    Button {
                        closePlaylist()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .buttonStyle(PlaylistFocusButtonStyle(isFocused: playlistFocus == .close, isRound: true))
                }

                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: playlistColumnCount), spacing: 10) {
                        ForEach(activeEpisodes) { episode in
                            let episodeIndex = activeEpisodes.firstIndex(where: { candidate in
                                candidate.id == episode.id && candidate.pageURL == episode.pageURL
                            }) ?? 0

                            PlaylistEpisodeCardLabel(
                                episode: episode,
                                isActive: episode.id == activeEpisode.id,
                                isFocused: playlistFocus == .episode(episodeIndex)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
            .padding(32)
            .frame(width: 680)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(.black.opacity(0.88))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)
            }
            .focusSection()
        }
    }

    private func handleSelect() {
        if viewModel.error != nil { return }
        if showingPlaylist {
            performPlaylistSelection()
            return
        }
        if viewModel.showControls {
            performFocusedControl()
        } else {
            showControls()
        }
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        if viewModel.error != nil { return }

        if showingPlaylist {
            movePlaylistFocus(direction)
            return
        }

        if viewModel.showControls {
            handleControlMoveCommand(direction)
            return
        }

        switch direction {
        case .left:
            seekBackward()
        case .right:
            seekForward()
        case .up, .down:
            showControls()
        default:
            showControls()
        }
    }

    private func handlePlayPauseCommand() {
        if viewModel.error != nil {
            retryPlaybackFromError()
            return
        }
        togglePlayPauseFromControls()
    }

    private func retryPlaybackFromError() {
        startPlaybackTask {
            if await retryAlternativePlaybackFromError() {
                return
            }

            if let activePlaybackSession, !activePlaybackSession.isUserSelected {
                print("PlayerView: 没有其它可重试的播放源或线路")
                return
            }

            await loadActiveEpisode()
        }
    }

    private func retryAlternativePlaybackFromError() async -> Bool {
        guard let activePlaybackSession, !activePlaybackSession.isUserSelected else {
            return false
        }

        markCurrentPlaybackAttemptFailed()

        if await switchToNextRoadForCurrentEpisode() {
            return true
        }

        if await switchToNextSourceForCurrentEpisode() {
            return true
        }

        return false
    }

    private func performFocusedControl() {
        switch focusedControl {
        case .progress:
            togglePlayPauseFromControls()

        case .nextEpisode:
            startPlaybackTask {
                await playAdjacentEpisode(1)
            }

        case .playlist:
            openPlaylist()

        case nil:
            togglePlayPauseFromControls()
        }
    }

    private func performPlaylistSelection() {
        switch playlistFocus {
        case .close:
            closePlaylist()

        case .episode(let index):
            guard activeEpisodes.indices.contains(index) else { return }
            startPlaybackTask {
                await switchToEpisode(activeEpisodes[index])
            }

        case nil:
            movePlaylistFocusToCurrentEpisode()
        }
    }

    private func handleControlMoveCommand(_ direction: MoveCommandDirection) {
        if focusedControl == .progress {
            switch direction {
            case .left:
                seekBackward()
                return
            case .right:
                seekForward()
                return
            default:
                break
            }
        }

        moveControlFocus(direction)
        scheduleControlsAutoHide()
    }

    private func moveControlFocus(_ direction: MoveCommandDirection) {
        let now = Date()
        guard now.timeIntervalSince(lastControlMoveAt) > 0.08 else { return }
        lastControlMoveAt = now

        let bottomControls = availableBottomControls

        guard let currentFocus = focusedControl else {
            focusedControl = defaultFocusedControl
            return
        }

        if currentFocus == .progress {
            guard direction == .down, let firstBottomControl = bottomControls.first else { return }
            focusedControl = firstBottomControl
            return
        }

        guard let currentIndex = bottomControls.firstIndex(of: currentFocus) else {
            focusedControl = defaultFocusedControl
            return
        }

        switch direction {
        case .left:
            if currentIndex > 0 {
                focusedControl = bottomControls[currentIndex - 1]
            }
        case .right:
            if currentIndex < bottomControls.count - 1 {
                focusedControl = bottomControls[currentIndex + 1]
            }
        case .up:
            focusedControl = .progress
        default:
            break
        }
    }

    private func movePlaylistFocus(_ direction: MoveCommandDirection) {
        let now = Date()
        guard now.timeIntervalSince(lastControlMoveAt) > 0.08 else { return }
        lastControlMoveAt = now

        let episodeCount = activeEpisodes.count

        guard episodeCount > 0 else {
            playlistFocus = .close
            return
        }

        switch playlistFocus {
        case .close:
            switch direction {
            case .down:
                movePlaylistFocusToCurrentEpisode()
            default:
                break
            }

        case .episode(let index):
            let clampedIndex = min(max(index, 0), max(episodeCount - 1, 0))
            switch direction {
            case .left:
                if clampedIndex > 0 {
                    playlistFocus = .episode(clampedIndex - 1)
                }
            case .right:
                if clampedIndex < episodeCount - 1 {
                    playlistFocus = .episode(clampedIndex + 1)
                }
            case .up:
                let nextIndex = clampedIndex - playlistColumnCount
                if nextIndex >= 0 {
                    playlistFocus = .episode(nextIndex)
                } else {
                    playlistFocus = .close
                }
            case .down:
                let nextIndex = clampedIndex + playlistColumnCount
                if nextIndex < episodeCount {
                    playlistFocus = .episode(nextIndex)
                }
            default:
                break
            }

        case nil:
            movePlaylistFocusToCurrentEpisode()
        }
    }

    private func movePlaylistFocusToCurrentEpisode() {
        let activeIndex = activeEpisodes.firstIndex { candidate in
            candidate.id == activeEpisode.id && candidate.pageURL == activeEpisode.pageURL
        } ?? activeEpisodes.firstIndex { candidate in
            candidate.id == activeEpisode.id
        } ?? 0

        if activeEpisodes.indices.contains(activeIndex) {
            playlistFocus = .episode(activeIndex)
        } else {
            playlistFocus = .close
        }
    }

    private var availableBottomControls: [PlayerControl] {
        var controls: [PlayerControl] = []
        if hasPlaylist {
            controls.append(.nextEpisode)
        }
        if activePlaybackSession != nil {
            controls.append(.playlist)
        }
        return controls
    }

    private var availableControls: [PlayerControl] {
        [.progress] + availableBottomControls
    }

    private var defaultFocusedControl: PlayerControl? {
        .progress
    }

    private func startPlaybackTask(_ operation: @escaping @MainActor () async -> Void) {
        episodeLoadTask?.cancel()
        episodeLoadTask = Task { @MainActor in
            await operation()
        }
    }

    private func togglePlayPauseFromControls() {
        viewModel.togglePlayPause()
        showControls(autoHide: false)
    }

    private func loadActiveEpisode() async {
        guard !Task.isCancelled else { return }
        let resumePosition = resumePositionForActiveEpisode()
        await viewModel.loadVideo(bangumi: bangumi, episode: activeEpisode, resumePosition: resumePosition)
        guard !Task.isCancelled else { return }
        if resumePosition != nil && viewModel.error == nil {
            pendingResumePosition = nil
            pendingResumeEpisodeNumber = nil
        }
        schedulePlaybackStartupWatchdog()
    }

    private func resumePositionForActiveEpisode() -> TimeInterval? {
        guard let position = pendingResumePosition, position > 1 else { return nil }
        if let episodeNumber = pendingResumeEpisodeNumber,
           episodeNumber != activeEpisode.episodeNumber {
            return nil
        }

        return position
    }

    private func openPlaylist() {
        showingPlaylist = true
        movePlaylistFocusToCurrentEpisode()
        showControls(autoHide: false)
    }

    private func closePlaylist() {
        showingPlaylist = false
        playlistFocus = nil
        showControls(focus: .playlist, autoHide: false)
    }

    private func switchToEpisode(_ episode: Episode) async {
        guard episode.id != activeEpisode.id || episode.pageURL != activeEpisode.pageURL else {
            closePlaylist()
            return
        }

        seekFeedbackTask?.cancel()
        cancelDirectionalSeekPreview()
        clearCommittedSeekDisplay()
        playbackStartupTask?.cancel()
        seekFeedback = nil
        pendingResumePosition = nil
        pendingResumeEpisodeNumber = nil
        savePlaybackProgressIfNeeded(force: true)
        viewModel.cleanup()

        activeEpisode = episode
        recordedPlaybackSuccess = false
        recordedPlaybackFailure = false
        resetPlaybackRetryTrail()

        closePlaylist()
        showControls(autoHide: false)
        await loadActiveEpisode()
    }

    private func schedulePlaybackStartupWatchdog() {
        playbackStartupTask?.cancel()
        let expectedEpisode = activeEpisode
        let expectedRoadID = selectedRoadID

        playbackStartupTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 75_000_000_000)
            guard !Task.isCancelled else { return }
            guard activeEpisode.id == expectedEpisode.id,
                  activeEpisode.pageURL == expectedEpisode.pageURL,
                  selectedRoadID == expectedRoadID else {
                return
            }

            guard !viewModel.isPlaying && viewModel.duration <= 0 else {
                return
            }

            print("PlayerView: 播放启动长时间无进展，准备切换线路: \(activeEpisode.pageURL ?? "nil")")
            recordPlaybackFailureIfNeeded()

            if await switchToNextRoadForCurrentEpisode() {
                return
            }

            if await switchToNextSourceForCurrentEpisode() {
                return
            }

            viewModel.forcePlaybackTimeout()
        }
    }

    private func switchToNextRoadForCurrentEpisode() async -> Bool {
        guard let activePlaybackSession,
              let currentRoad = activeRoad,
              let currentRoadIndex = activePlaybackSession.roads.firstIndex(where: { $0.id == currentRoad.id }) else {
            return false
        }

        let currentEpisodeIndex = currentRoad.episodes.firstIndex { candidate in
            candidate.id == activeEpisode.id && candidate.pageURL == activeEpisode.pageURL
        } ?? currentRoad.episodes.firstIndex { candidate in
            candidate.episodeNumber == activeEpisode.episodeNumber
        } ?? 0

        let orderedRoads = Array(activePlaybackSession.roads.dropFirst(currentRoadIndex + 1)) +
            Array(activePlaybackSession.roads.prefix(currentRoadIndex))

        guard let nextRoad = orderedRoads.first(where: { road in
            !road.episodes.isEmpty &&
            !failedPlaybackRoadKeys.contains(playbackRoadKey(session: activePlaybackSession, road: road))
        }) else {
            failedPlaybackSourceKeys.insert(playbackSourceKey(activePlaybackSession.source))
            return false
        }

        let nextEpisode: Episode
        if nextRoad.episodes.indices.contains(currentEpisodeIndex) {
            nextEpisode = nextRoad.episodes[currentEpisodeIndex]
        } else if let matchingEpisode = nextRoad.episodes.first(where: { $0.episodeNumber == activeEpisode.episodeNumber }) {
            nextEpisode = matchingEpisode
        } else {
            nextEpisode = nextRoad.episodes[0]
        }

        print("PlayerView: 自动切换到线路 \(nextRoad.name), episode=\(nextEpisode.displayName)")
        self.activePlaybackSession = PlaybackSession(
            bangumi: activePlaybackSession.bangumi,
            source: activePlaybackSession.source,
            candidateSources: activePlaybackSession.candidateSources,
            roads: activePlaybackSession.roads,
            selectedRoadID: nextRoad.id,
            selectedEpisodeID: nextEpisode.id,
            resumePosition: nil,
            isUserSelected: false
        )
        selectedRoadID = nextRoad.id
        activeEpisode = nextEpisode
        recordedPlaybackSuccess = false
        recordedPlaybackFailure = false
        cancelDirectionalSeekPreview()
        clearCommittedSeekDisplay()
        viewModel.cleanup()
        showControls(autoHide: false)
        await loadActiveEpisode()
        return true
    }

    private func switchToNextSourceForCurrentEpisode() async -> Bool {
        guard let activePlaybackSession else { return false }

        let currentPluginName = activePlaybackSession.source.pluginName
        let currentSourceURL = activePlaybackSession.source.src
        failedPlaybackSourceKeys.insert(playbackSourceKey(activePlaybackSession.source))
        let candidates = SourcePlaybackPreferenceStore.shared.sortedSources(activePlaybackSession.candidateSources)

        for candidate in candidates {
            let candidateKey = playbackSourceKey(candidate)
            guard candidate.pluginName != currentPluginName || candidate.src != currentSourceURL else {
                continue
            }
            guard !failedPlaybackSourceKeys.contains(candidateKey) else {
                continue
            }

            do {
                let roads = try await loadPlaybackRoads(from: candidate)
                guard !roads.isEmpty else {
                    failedPlaybackSourceKeys.insert(candidateKey)
                    SourcePlaybackPreferenceStore.shared.recordFailure(pluginName: candidate.pluginName)
                    continue
                }

                let targetEpisodeNumber = activeEpisode.episodeNumber
                let targetIndex = activeEpisodes.firstIndex { episode in
                    episode.id == activeEpisode.id && episode.pageURL == activeEpisode.pageURL
                } ?? max(0, targetEpisodeNumber - 1)

                guard let selectedRoad = preferredPlaybackRoad(from: roads, pluginName: candidate.pluginName),
                      !selectedRoad.episodes.isEmpty else {
                    failedPlaybackSourceKeys.insert(candidateKey)
                    SourcePlaybackPreferenceStore.shared.recordFailure(pluginName: candidate.pluginName)
                    continue
                }

                let nextEpisode: Episode
                if let matchingEpisode = selectedRoad.episodes.first(where: { $0.episodeNumber == targetEpisodeNumber }) {
                    nextEpisode = matchingEpisode
                } else if selectedRoad.episodes.indices.contains(targetIndex) {
                    nextEpisode = selectedRoad.episodes[targetIndex]
                } else {
                    nextEpisode = selectedRoad.episodes[0]
                }

                print("PlayerView: 自动切换到播放源 \(candidate.pluginName), 线路 \(selectedRoad.name), episode=\(nextEpisode.displayName)")
                self.activePlaybackSession = PlaybackSession(
                    bangumi: activePlaybackSession.bangumi,
                    source: candidate,
                    candidateSources: candidates.filter { $0.pluginName != candidate.pluginName || $0.src != candidate.src },
                    roads: roads,
                    selectedRoadID: selectedRoad.id,
                    selectedEpisodeID: nextEpisode.id,
                    isUserSelected: false
                )
                selectedRoadID = selectedRoad.id
                activeEpisode = nextEpisode
                recordedPlaybackSuccess = false
                recordedPlaybackFailure = false
                cancelDirectionalSeekPreview()
                clearCommittedSeekDisplay()
                viewModel.cleanup()
                showControls(autoHide: false)
                await loadActiveEpisode()
                return true
            } catch {
                print("PlayerView: 播放源 \(candidate.pluginName) 自动切换失败: \(error)")
                failedPlaybackSourceKeys.insert(candidateKey)
                SourcePlaybackPreferenceStore.shared.recordFailure(pluginName: candidate.pluginName)
            }
        }

        return false
    }

    private func loadPlaybackRoads(from source: SearchItem) async throws -> [PlaybackRoad] {
        let pluginManager = PluginManager.shared
        try await pluginManager.loadPlugins()
        guard let plugin = await pluginManager.getPlugin(name: source.pluginName) else {
            throw PluginError.pluginNotFound(source.pluginName)
        }

        let roads = try await pluginManager.getChapters(pageURL: source.src, plugin: plugin)
        return roads
            .filter { !$0.episodes.isEmpty }
            .map { road in
                PlaybackRoad(
                    id: road.id,
                    name: road.name,
                    episodes: playbackEpisodes(from: road, pluginName: source.pluginName)
                )
            }
            .filter { !$0.episodes.isEmpty }
    }

    private func playbackEpisodes(from road: ChapterRoad, pluginName: String) -> [Episode] {
        road.episodes.enumerated().map { index, item in
            Episode(
                id: -((index + 1) * 10_000 + stableEpisodeSuffix(from: "\(pluginName)-\(road.id)-\(item.src)")),
                bangumiId: bangumi.id,
                episodeNumber: item.episode,
                name: item.name.isEmpty ? "第 \(item.episode) 集" : item.name,
                nameCn: "",
                airDate: "",
                duration: "",
                description: "",
                type: .normal,
                pageURL: item.src,
                pluginName: pluginName
            )
        }
    }

    private func preferredPlaybackRoad(from roads: [PlaybackRoad], pluginName: String) -> PlaybackRoad? {
        let chapterRoads = roads.map { road in
            ChapterRoad(
                id: road.id,
                name: road.name,
                episodes: road.episodes.map { episode in
                    ChapterRoad.EpisodeItem(
                        id: "\(episode.id)",
                        name: episode.displayName,
                        src: episode.pageURL ?? "",
                        episode: episode.episodeNumber
                    )
                }
            )
        }

        if let preferred = SourcePlaybackPreferenceStore.shared.preferredRoad(in: chapterRoads, pluginName: pluginName),
           let road = roads.first(where: { $0.id == preferred.id }) {
            return road
        }

        if pluginName.lowercased() == "age",
           let firstRoad = roads.first(where: { $0.id == "age-road-1" || $0.name == "线路 1" }) {
            return firstRoad
        }

        return roads.first
    }

    private func stableEpisodeSuffix(from value: String) -> Int {
        value.unicodeScalars.reduce(0) { partialResult, scalar in
            (partialResult &* 31 &+ Int(scalar.value)) % 9_999
        }
    }

    private func recordPlaybackSuccessIfNeeded() {
        guard !recordedPlaybackSuccess,
              let activePlaybackSession,
              let activeRoad else {
            return
        }

        SourcePlaybackPreferenceStore.shared.recordSuccess(
            pluginName: activePlaybackSession.source.pluginName,
            roadID: activeRoad.id,
            roadName: activeRoad.name,
            episodeCount: activeRoad.episodes.count,
            isUserSelected: activePlaybackSession.isUserSelected
        )
        recordedPlaybackSuccess = true
    }

    private func recordPlaybackFailureIfNeeded() {
        guard !recordedPlaybackFailure,
              let activePlaybackSession,
              let activeRoad else {
            return
        }

        markCurrentPlaybackAttemptFailed()
        SourcePlaybackPreferenceStore.shared.recordFailure(
            pluginName: activePlaybackSession.source.pluginName,
            roadID: activeRoad.id,
            roadName: activeRoad.name,
            episodeCount: activeRoad.episodes.count
        )
        recordedPlaybackFailure = true
    }

    private func markCurrentPlaybackAttemptFailed() {
        guard let activePlaybackSession else { return }

        if let activeRoad {
            failedPlaybackRoadKeys.insert(playbackRoadKey(session: activePlaybackSession, road: activeRoad))
        } else {
            failedPlaybackSourceKeys.insert(playbackSourceKey(activePlaybackSession.source))
        }
    }

    private func resetPlaybackRetryTrail() {
        failedPlaybackRoadKeys.removeAll()
        failedPlaybackSourceKeys.removeAll()
    }

    private func playbackSourceKey(_ source: SearchItem) -> String {
        "\(source.pluginName)|\(source.src)"
    }

    private func playbackRoadKey(session: PlaybackSession, road: PlaybackRoad) -> String {
        "\(playbackSourceKey(session.source))|\(road.id)"
    }

    private func savePlaybackProgressIfNeeded(currentTime: TimeInterval? = nil, force: Bool = false) {
        let now = Date().timeIntervalSince1970
        guard force || now - lastHistorySaveTime >= 12 else { return }

        let currentTime = currentTime ?? viewModel.currentTime
        let duration = viewModel.duration
        let progress = duration > 0 ? min(max(currentTime, 0), duration) : max(currentTime, 0)
        guard recordedPlaybackSuccess || viewModel.isPlaying else { return }
        guard progress > 0, force || progress >= 5 else { return }
        guard let source = historySourceInfo() else { return }

        lastHistorySaveTime = now
        let bangumiImage = bangumi.images["large"]
            ?? bangumi.images["common"]
            ?? bangumi.images["grid"]
            ?? bangumi.images["medium"]
            ?? ""
        let progressRatio = duration > 0 ? min(max(progress / duration, 0), 1) : 0
        let episodeSnapshot = activeEpisode
        let bangumiSnapshot = bangumi

        Task {
            do {
                try await HistoryRepository.shared.addHistory(
                    bangumiId: bangumiSnapshot.id,
                    episodeId: episodeSnapshot.id,
                    episodeNumber: episodeSnapshot.episodeNumber,
                    episodeName: episodeSnapshot.displayName,
                    bangumiName: bangumiSnapshot.displayName,
                    bangumiImage: bangumiImage,
                    progress: progress,
                    duration: duration,
                    source: source.pluginName,
                    sourceURL: source.sourceURL,
                    sourceName: source.sourceName
                )

                if duration > 0 {
                    try await FavoriteRepository.shared.updateWatchProgress(
                        bangumiId: bangumiSnapshot.id,
                        episode: episodeSnapshot.episodeNumber,
                        progress: progressRatio
                    )
                }
            } catch {
                print("PlayerView: failed to save playback progress: \(error)")
            }
        }
    }

    private func historySourceInfo() -> PlaybackHistorySourceInfo? {
        if let source = activePlaybackSession?.source {
            return PlaybackHistorySourceInfo(
                pluginName: source.pluginName,
                sourceURL: source.src,
                sourceName: source.displayName
            )
        }

        let pluginName = (activeEpisode.pluginName ?? viewModel.currentSource?.pluginName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceURL = (activeEpisode.pageURL ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !pluginName.isEmpty || !sourceURL.isEmpty else {
            return nil
        }

        return PlaybackHistorySourceInfo(
            pluginName: pluginName,
            sourceURL: sourceURL,
            sourceName: bangumi.displayName
        )
    }

    private func playAdjacentEpisode(_ offset: Int) async {
        guard let index = activeEpisodes.firstIndex(where: { $0.id == activeEpisode.id }) else {
            return
        }

        let nextIndex = index + offset
        guard activeEpisodes.indices.contains(nextIndex) else {
            return
        }

        await switchToEpisode(activeEpisodes[nextIndex])
    }

    private func seekBackward() {
        adjustDirectionalSeek(by: -directionalSeekStep, feedback: .backward)
    }

    private func seekForward() {
        adjustDirectionalSeek(by: directionalSeekStep, feedback: .forward)
    }

    private func adjustDirectionalSeek(by delta: TimeInterval, feedback: SeekFeedback) {
        viewModel.beginInteractiveSeek()

        if viewModel.duration <= 0 {
            delta < 0 ? viewModel.seekBackward() : viewModel.seekForward()
            showSeekFeedback(feedback)
            return
        }

        cancelControlsAutoHide()
        let baseTime = scrubPreviewTime ?? committedSeekDisplayTime ?? viewModel.currentTime
        let targetTime = min(max(baseTime + delta, 0), viewModel.duration)
        scrubPreviewTime = targetTime
        committedSeekDisplayTime = nil
        showSeekFeedback(feedback)

        directionalSeekCommitTask?.cancel()
        directionalSeekCommitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: directionalSeekCommitDelay)
            guard !Task.isCancelled else { return }
            commitDirectionalSeek(scrubPreviewTime ?? targetTime)
        }
    }

    private func commitDirectionalSeek(_ targetTime: TimeInterval) {
        viewModel.seek(to: targetTime)
        holdCommittedSeekDisplay(targetTime)
        scrubPreviewTime = nil
        directionalSeekCommitTask = nil

        if viewModel.showControls {
            showControls(focus: focusedControl, autoHide: viewModel.isPlaying)
        }
    }

    private func cancelDirectionalSeekPreview() {
        directionalSeekCommitTask?.cancel()
        directionalSeekCommitTask = nil
        scrubPreviewTime = nil
    }

    private func holdCommittedSeekDisplay(_ targetTime: TimeInterval) {
        committedSeekDisplayTask?.cancel()
        committedSeekDisplayTime = targetTime
        committedSeekDisplayTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }
            clearCommittedSeekDisplay()
        }
    }

    private func clearCommittedSeekDisplayIfReached(_ currentTime: TimeInterval) {
        guard let committedSeekDisplayTime else { return }
        if abs(currentTime - committedSeekDisplayTime) <= 0.75 {
            clearCommittedSeekDisplay()
        }
    }

    private func clearCommittedSeekDisplay() {
        committedSeekDisplayTask?.cancel()
        committedSeekDisplayTask = nil
        committedSeekDisplayTime = nil
    }

    private func beginRemoteScrub(_ targetTime: TimeInterval) {
        directionalSeekCommitTask?.cancel()
        clearCommittedSeekDisplay()
        cancelControlsAutoHide()
        viewModel.beginInteractiveSeek()
        scrubPreviewTime = targetTime
    }

    private func updateRemoteScrub(_ targetTime: TimeInterval) {
        scrubPreviewTime = targetTime
    }

    private func commitRemoteScrub(_ targetTime: TimeInterval) {
        directionalSeekCommitTask?.cancel()
        viewModel.seek(to: targetTime)
        holdCommittedSeekDisplay(targetTime)
        scrubPreviewTime = nil
        showControls(autoHide: viewModel.isPlaying)
    }

    private func showControls(focus: PlayerControl? = nil, autoHide: Bool = true) {
        viewModel.showControls = true
        if let focus, availableControls.contains(focus) {
            focusedControl = focus
        } else if focusedControl.map({ !availableControls.contains($0) }) ?? true {
            focusedControl = defaultFocusedControl
        }

        if autoHide {
            scheduleControlsAutoHide()
        } else {
            cancelControlsAutoHide()
        }
    }

    private func hideControls() {
        cancelControlsAutoHide()
        focusedControl = nil
        viewModel.showControls = false
    }

    private func scheduleControlsAutoHide() {
        hideControlsTask?.cancel()
        guard viewModel.isPlaying, viewModel.error == nil else { return }

        hideControlsTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, viewModel.isPlaying, !viewModel.isBuffering else { return }
            focusedControl = nil
            viewModel.showControls = false
        }
    }

    private func cancelControlsAutoHide() {
        hideControlsTask?.cancel()
        hideControlsTask = nil
    }

    private func showSeekFeedback(_ feedback: SeekFeedback) {
        seekFeedbackTask?.cancel()
        withAnimation(.easeOut(duration: 0.12)) {
            seekFeedback = feedback
        }

        seekFeedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.16)) {
                seekFeedback = nil
            }
        }
    }

    private func formatPlayerTime(_ time: TimeInterval) -> String {
        let clampedTime = max(0, time)
        let hours = Int(clampedTime) / 3600
        let minutes = (Int(clampedTime) % 3600) / 60
        let seconds = Int(clampedTime) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private enum PlayerControl: Hashable {
    case progress
    case playlist
    case nextEpisode
}

private struct PlaybackHistorySourceInfo {
    let pluginName: String
    let sourceURL: String
    let sourceName: String
}

private enum PlaylistFocus: Hashable {
    case close
    case episode(Int)
}

private enum SeekFeedback {
    case backward
    case forward

    var icon: String {
        switch self {
        case .backward:
            return "gobackward.5"
        case .forward:
            return "goforward.5"
        }
    }
}

private struct PlaylistEpisodeCardLabel: View {
    let episode: Episode
    let isActive: Bool
    let isFocused: Bool

    var body: some View {
        Text(episode.displayName)
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundColor(isFocused ? .white : (isActive ? .kzPrimary : .white))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .allowsTightening(true)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .center)
        .padding(.horizontal, 14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .scaleEffect(isFocused ? 1.012 : 1.0)
        .shadow(color: isFocused ? Color.kzPrimary.opacity(0.24) : Color.clear, radius: 10)
        .animation(.easeOut(duration: 0.14), value: isFocused)
    }

    private var cardBackground: Color {
        if isFocused {
            return Color.kzPrimary.opacity(0.70)
        }
        return isActive ? Color.kzPrimaryContainer.opacity(0.22) : Color.white.opacity(0.07)
    }
}

private struct PlaylistFocusButtonStyle: ButtonStyle {
    let isFocused: Bool
    let isRound: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(isRound ? 14 : 0)
            .background(
                Group {
                    if isRound {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isFocused ? Color.kzPrimary.opacity(0.74) : Color.white.opacity(0.08))
                    } else {
                        Capsule()
                            .fill(isFocused ? Color.kzPrimary.opacity(0.74) : Color.clear)
                    }
                }
            )
            .overlay {
                Group {
                    if isRound {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isFocused ? Color.white.opacity(0.88) : Color.clear, lineWidth: 2)
                    } else {
                        Capsule()
                            .stroke(isFocused ? Color.white.opacity(0.88) : Color.clear, lineWidth: 2)
                    }
                }
            }
            .scaleEffect(isFocused ? 1.045 : 1.0)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .shadow(color: isFocused ? Color.kzPrimary.opacity(0.34) : Color.clear, radius: 16)
            .animation(.easeOut(duration: 0.14), value: isFocused)
    }
}

private struct PlayerTransportButtonStyle: ButtonStyle {
    let isFocused: Bool
    let isPrimary: Bool

    init(isFocused: Bool, isPrimary: Bool = false) {
        self.isFocused = isFocused
        self.isPrimary = isPrimary
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: isPrimary ? 34 : 16, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay {
                RoundedRectangle(cornerRadius: isPrimary ? 34 : 16, style: .continuous)
                    .stroke(isFocused ? Color.white.opacity(0.92) : Color.clear, lineWidth: 2)
            }
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .shadow(color: isFocused ? Color.kzPrimary.opacity(0.42) : Color.clear, radius: 20)
            .animation(.easeOut(duration: 0.14), value: isFocused)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }

    private var backgroundColor: Color {
        if isFocused {
            return isPrimary ? Color.kzPrimary.opacity(0.94) : Color.white.opacity(0.18)
        }
        return isPrimary ? Color.white.opacity(0.12) : Color.white.opacity(0.08)
    }
}

private struct PlayerProgressBar: View {
    let progress: Double
    let isScrubbing: Bool
    let isFocused: Bool

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let centerY = proxy.size.height / 2
            let knobX = clampedProgress * width
            let trackHeight: CGFloat = isFocused ? 8 : 6
            let knobSize: CGFloat = isScrubbing ? 24 : (isFocused ? 20 : 14)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(isFocused ? 0.16 : 0))
                    .frame(height: isFocused ? 14 : 0)
                    .position(x: width / 2, y: centerY)

                Capsule()
                    .fill(Color.kzTextSecondary.opacity(isFocused ? 0.36 : 0.28))
                    .frame(height: trackHeight)
                    .position(x: width / 2, y: centerY)

                Capsule()
                    .fill(Color.kzPrimary)
                    .frame(width: max(0, knobX), height: trackHeight)
                    .position(x: max(0, knobX) / 2, y: centerY)

                Circle()
                    .fill(Color.kzPrimary)
                    .frame(width: knobSize, height: knobSize)
                    .overlay {
                        if isScrubbing || isFocused {
                            Circle()
                                .stroke(Color.kzOnPrimaryContainer.opacity(0.92), lineWidth: 3)
                        }
                    }
                    .shadow(
                        color: Color.kzPrimary.opacity((isScrubbing || isFocused) ? 0.64 : 0.24),
                        radius: (isScrubbing || isFocused) ? 16 : 6
                    )
                    .position(x: min(max(knobX, 0), width), y: centerY)
                    .animation(.easeOut(duration: 0.12), value: isScrubbing || isFocused)
                    .animation(.linear(duration: 0.08), value: clampedProgress)
            }
        }
    }
}

// MARK: - Video Player Layer
struct VideoPlayerLayer: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.player = player
    }
}

class PlayerUIView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            playerLayer.player = newValue
            playerLayer.videoGravity = .resizeAspect
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

// MARK: - Remote Scrubbing

private struct RemoteScrubGestureLayer: UIViewRepresentable {
    let isEnabled: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onBegin: (TimeInterval) -> Void
    let onChange: (TimeInterval) -> Void
    let onEnd: (TimeInterval) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            currentTime: currentTime,
            duration: duration,
            onBegin: onBegin,
            onChange: onChange,
            onEnd: onEnd
        )
    }

    func makeUIView(context: Context) -> RemoteScrubUIView {
        let view = RemoteScrubUIView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: RemoteScrubUIView, context: Context) {
        uiView.isUserInteractionEnabled = isEnabled
        context.coordinator.isEnabled = isEnabled
        context.coordinator.currentTime = currentTime
        context.coordinator.duration = duration
        context.coordinator.onBegin = onBegin
        context.coordinator.onChange = onChange
        context.coordinator.onEnd = onEnd
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isEnabled = false
        var currentTime: TimeInterval
        var duration: TimeInterval
        var onBegin: (TimeInterval) -> Void
        var onChange: (TimeInterval) -> Void
        var onEnd: (TimeInterval) -> Void

        private var baseTime: TimeInterval = 0
        private var lastPoint: CGPoint?
        private var lastMovementAngle: CGFloat?
        private var filteredAccumulatedAngle: CGFloat = 0
        private var lockedDirection: CGFloat = 0
        private var reverseAngle: CGFloat = 0
        private var targetTime: TimeInterval = 0
        private var hasStartedScrubbing = false

        init(
            currentTime: TimeInterval,
            duration: TimeInterval,
            onBegin: @escaping (TimeInterval) -> Void,
            onChange: @escaping (TimeInterval) -> Void,
            onEnd: @escaping (TimeInterval) -> Void
        ) {
            self.currentTime = currentTime
            self.duration = duration
            self.onBegin = onBegin
            self.onChange = onChange
            self.onEnd = onEnd
        }

        func attach(to view: UIView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.cancelsTouchesInView = false
            pan.delaysTouchesBegan = false
            pan.delaysTouchesEnded = false
            pan.delegate = self
            #if os(tvOS)
            pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            #endif
            view.addGestureRecognizer(pan)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            isEnabled && duration > 0
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard isEnabled, duration > 0, let view = recognizer.view else { return }

            switch recognizer.state {
            case .began:
                baseTime = currentTime
                targetTime = currentTime
                filteredAccumulatedAngle = 0
                lockedDirection = 0
                reverseAngle = 0
                hasStartedScrubbing = false
                lastPoint = recognizer.location(in: view)
                lastMovementAngle = nil

            case .changed:
                let point = recognizer.location(in: view)
                guard let previousPoint = lastPoint else {
                    lastPoint = point
                    return
                }

                let movement = CGVector(dx: point.x - previousPoint.x, dy: point.y - previousPoint.y)
                lastPoint = point

                guard hypot(movement.dx, movement.dy) >= 1.2 else {
                    return
                }

                let movementAngle = atan2(movement.dy, movement.dx)
                guard let previousMovementAngle = lastMovementAngle else {
                    lastMovementAngle = movementAngle
                    return
                }

                lastMovementAngle = movementAngle

                let rawDelta = normalizedAngleDelta(movementAngle - previousMovementAngle)
                guard let acceptedDelta = filteredAngularDelta(rawDelta) else {
                    return
                }

                filteredAccumulatedAngle += acceptedDelta
                if lockedDirection == 0, abs(filteredAccumulatedAngle) >= 0.16 {
                    lockedDirection = filteredAccumulatedAngle > 0 ? 1 : -1
                }

                guard abs(filteredAccumulatedAngle) >= 0.16 || hasStartedScrubbing else { return }

                let secondsPerRotation = min(max(duration / 20, 45), 120) * 1.4
                let deltaSeconds = TimeInterval(filteredAccumulatedAngle / (2 * CGFloat.pi)) * secondsPerRotation
                targetTime = max(0, min(duration, baseTime + deltaSeconds))

                if !hasStartedScrubbing {
                    hasStartedScrubbing = true
                    onBegin(targetTime)
                } else {
                    onChange(targetTime)
                }

            case .ended, .cancelled, .failed:
                if hasStartedScrubbing {
                    onEnd(targetTime)
                }
                reset()

            default:
                break
            }
        }

        private func normalizedAngleDelta(_ delta: CGFloat) -> CGFloat {
            var normalized = delta
            if normalized > CGFloat.pi {
                normalized -= 2 * CGFloat.pi
            } else if normalized < -CGFloat.pi {
                normalized += 2 * CGFloat.pi
            }
            return normalized
        }

        private func filteredAngularDelta(_ delta: CGFloat) -> CGFloat? {
            let magnitude = abs(delta)
            guard magnitude >= 0.006, magnitude <= 1.2 else { return nil }

            let direction: CGFloat = delta > 0 ? 1 : -1
            guard lockedDirection != 0 else {
                reverseAngle = 0
                return delta
            }

            if direction == lockedDirection {
                reverseAngle = 0
                return delta
            }

            reverseAngle += magnitude
            guard reverseAngle >= 0.45 else {
                return nil
            }

            lockedDirection = direction
            let acceptedDelta = direction * reverseAngle
            reverseAngle = 0
            return acceptedDelta
        }

        private func reset() {
            lastPoint = nil
            lastMovementAngle = nil
            filteredAccumulatedAngle = 0
            lockedDirection = 0
            reverseAngle = 0
            hasStartedScrubbing = false
            targetTime = 0
        }
    }
}

private final class RemoteScrubUIView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

#Preview {
    PlayerView(
        bangumi: Bangumi.sample,
        episode: Episode.sample
    )
}
