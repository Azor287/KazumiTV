//
//  BangumiDetailView.swift
//  KazumiTV
//
//  Kazumi-style detail screen adapted for tvOS focus navigation.
//

import SwiftUI
import Kingfisher

struct BangumiDetailView: View {
    let bangumi: Bangumi
    let searchItem: SearchItem?

    private let rightInfoColumnWidth: CGFloat = 470

    @StateObject private var viewModel = BangumiDetailViewModel()
    @ObservedObject private var router = Router.shared
    @Environment(\.resetFocus) private var resetFocus
    @Namespace private var collectionMenuFocusScope
    @FocusState private var focusedElement: DetailFocus?
    @FocusState private var focusedCollectionStatus: CollectionStatus?
    @State private var lastFocusedCollectionStatus: CollectionStatus?
    @State private var selectedTab: DetailTab = .overview
    @State private var showingSourceSheet = false
    @State private var showingCollectionMenu = false

    private var displayedBangumi: Bangumi {
        viewModel.fullBangumi ?? bangumi
    }

    private var detailTitle: String {
        if !bangumi.displayName.isEmpty {
            return bangumi.displayName
        }

        return displayedBangumi.displayName
    }

    var body: some View {
        ZStack(alignment: .top) {
            detailBackground

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    heroSection
                        .zIndex(showingCollectionMenu ? 30 : 0)
                    tabBar
                        .disabled(showingCollectionMenu)
                        .zIndex(0)
                    detailContent
                        .disabled(showingCollectionMenu)
                        .zIndex(0)
                }
                .padding(.horizontal, 72)
                .padding(.top, 34)
                .padding(.bottom, 72)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(showingCollectionMenu)
            .disabled(showingSourceSheet)
            .allowsHitTesting(!showingSourceSheet)

            if showingSourceSheet {
                sourceSelectionOverlay
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .background(Color.kzBackground)
        .navigationBarHidden(true)
        .animation(.easeOut(duration: 0.16), value: showingSourceSheet)
        .onAppear {
            scheduleStartWatchingFocus()
        }
        .onChange(of: showingSourceSheet) { _, isShowing in
            if isShowing {
                focusedElement = nil
            } else {
                scheduleStartWatchingFocus()
            }
        }
        .onChange(of: showingCollectionMenu) { _, isShowing in
            if isShowing {
                focusedElement = nil
                focusedCollectionStatus = nil
                lastFocusedCollectionStatus = viewModel.collectionStatus
                scheduleCollectionMenuFocus()
            } else {
                focusedCollectionStatus = nil
                lastFocusedCollectionStatus = nil
                focusedElement = .collect
            }
        }
        .onChange(of: focusedCollectionStatus) { _, newValue in
            guard showingCollectionMenu else { return }
            if let newValue {
                lastFocusedCollectionStatus = newValue
            } else {
                scheduleCollectionMenuFocus(preferredStatus: lastFocusedCollectionStatus)
            }
        }
        .onChange(of: selectedTab) { _, tab in
            loadTabDataIfNeeded(tab)
        }
        .onChange(of: viewModel.isSearchingSources) { _, isSearching in
            guard !isSearching else { return }
            loadEpisodesForChapterTabIfNeeded()
        }
        .onExitCommand {
            if showingSourceSheet {
                showingSourceSheet = false
            } else if showingCollectionMenu {
                dismissCollectionMenu()
            } else {
                router.pop()
            }
        }
        .task {
            await viewModel.loadData(bangumi: bangumi, searchItem: searchItem)
            scheduleStartWatchingFocus()
        }
    }

    private var sourceSelectionOverlay: some View {
        ZStack {
            Color.black.opacity(0.52)
                .ignoresSafeArea()

            SourceSelectionSheet(
                bangumi: displayedBangumi,
                sourceItem: viewModel.playbackSource ?? searchItem,
                sourcePluginTabs: viewModel.sourcePluginTabs,
                selectedPluginName: viewModel.selectedSourcePluginName,
                sourceQueryKeyword: viewModel.sourceQueryKeyword,
                sourceCandidates: viewModel.sourceCandidates,
                sourceRoads: viewModel.sourceRoads,
                selectedRoadID: viewModel.selectedRoadID,
                episodes: viewModel.playableEpisodes,
                isLoading: viewModel.isPreparingPlayback,
                loadingSourceKey: viewModel.loadingSourceKey,
                sourceSelectionError: viewModel.sourceSelectionError,
                selectPluginTab: selectPluginTab,
                selectSource: selectSource,
                selectRoad: selectRoad,
                retryPlugin: retryPlugin,
                searchAliasForPlugin: searchAliasForPlugin,
                manualSearchForPlugin: manualSearchForPlugin,
                playEpisode: playEpisode,
                dismiss: { showingSourceSheet = false }
            )
        }
        .ignoresSafeArea()
    }

    private var detailBackground: some View {
        ZStack(alignment: .top) {
            if let imageURL = displayedBangumi.largeImage {
                KFImage(imageURL)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 380)
                    .clipped()
                    .blur(radius: 18)
                    .opacity(0.34)
                    .overlay(
                        LinearGradient(
                            colors: [
                                Color.kzBackground.opacity(0.05),
                                Color.kzBackground.opacity(0.72),
                                Color.kzBackground
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .ignoresSafeArea()
            }

            LinearGradient(
                colors: [
                    Color.kzBackground.opacity(0.22),
                    Color.kzBackground.opacity(0.88),
                    Color.kzBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(detailTitle)
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(Color.kzText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 28) {
                posterView

                VStack(alignment: .leading, spacing: 18) {
                    KazumiMetricBlock(title: "放送开始:", value: displayedBangumi.airDate.isEmpty ? "未知" : displayedBangumi.airDate)

                    if displayedBangumi.ratingScore > 0 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(displayedBangumi.votes) 人评分:")
                                .font(.headline)
                                .foregroundStyle(Color.kzText)

                            HStack(spacing: 10) {
                                Text(String(format: "%.1f", displayedBangumi.ratingScore))
                                    .font(.system(size: 30, weight: .bold))
                                    .foregroundStyle(Color.kzPrimary.opacity(0.78))

                                StarRating(score: displayedBangumi.ratingScore)
                            }
                        }
                    }

                    if displayedBangumi.rank > 0 {
                        KazumiMetricBlock(title: "Bangumi Ranked:", value: "#\(displayedBangumi.rank)")
                    }

                    Spacer(minLength: 12)

                    heroActions
                }
                .frame(minWidth: 440, idealWidth: 440, maxWidth: 440, minHeight: 320, alignment: .topLeading)

                Spacer(minLength: 120)

                if displayedBangumi.ratingScore > 0, !displayedBangumi.votesCount.isEmpty {
                    RatingHistogram(votesCount: displayedBangumi.votesCount)
                        .frame(width: rightInfoColumnWidth, height: 280, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heroActions: some View {
        HStack(spacing: 14) {
            Button {
                showingSourceSheet = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "play.fill")
                    Text("开始观看")
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.kzOnPrimaryContainer)
                    .frame(minWidth: 208, minHeight: 56)
                    .padding(.horizontal, 22)
                    .contentShape(Capsule())
            }
            .buttonStyle(HeroActionButtonStyle(isPrimary: true))
            .disabled(showingCollectionMenu)
            .focused($focusedElement, equals: .startWatching)

            collectionMenu
        }
        .zIndex(showingCollectionMenu ? 4 : 0)
    }

    private var collectionMenu: some View {
        ZStack(alignment: .topLeading) {
            Button {
                if showingCollectionMenu {
                    dismissCollectionMenu()
                } else {
                    presentCollectionMenu()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: viewModel.collectionStatus.iconName)
                    Text(viewModel.collectionStatus.title)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.kzOnPrimaryContainer)
                .frame(minWidth: 150, minHeight: 56)
                .padding(.horizontal, 22)
                .contentShape(Capsule())
            }
            .buttonStyle(HeroActionButtonStyle(isPrimary: false))
            .disabled(showingCollectionMenu)
            .focused($focusedElement, equals: .collect)

            collectionStatusMenu
                .offset(y: 68)
        }
        .frame(width: 194, height: 56, alignment: .topLeading)
        .zIndex(showingCollectionMenu ? 20 : 0)
    }

    @ViewBuilder
    private var collectionStatusMenu: some View {
        if showingCollectionMenu {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(CollectionStatus.allCases, id: \.self) { status in
                    Button {
                        Task {
                            await viewModel.setCollectionStatus(status, bangumi: displayedBangumi)
                            dismissCollectionMenu()
                        }
                    } label: {
                        HStack(spacing: 22) {
                            Image(systemName: status.iconName)
                                .font(.system(size: 32, weight: .semibold))
                                .frame(width: 42)

                            Text(status.title)
                                .font(.system(size: 30, weight: .semibold))
                        }
                        .foregroundStyle(focusedCollectionStatus == status ? Color.kzOnPrimaryContainer : Color.kzText)
                        .frame(width: 244, height: 74, alignment: .leading)
                        .padding(.horizontal, 18)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(CollectionMenuButtonStyle())
                    .focused($focusedCollectionStatus, equals: status)
                    .prefersDefaultFocus(status == viewModel.collectionStatus, in: collectionMenuFocusScope)
                }
            }
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.kzSurfaceContainer.opacity(0.96))
            )
            .zIndex(20)
            .focusScope(collectionMenuFocusScope)
            .focusSection()
            .onAppear {
                scheduleCollectionMenuFocus()
            }
            .onExitCommand {
                dismissCollectionMenu()
            }
        }
    }

    private var posterView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.kzCardBackground)

            if let imageURL = displayedBangumi.largeImage {
                KFImage(imageURL)
                    .placeholder {
                        ProgressView()
                            .tint(.kzPrimary)
                    }
                    .retry(maxCount: 2, interval: .seconds(1))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(Color.kzTextSecondary)
            }
        }
        .frame(width: 210, height: 323)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var tabBar: some View {
        HStack(spacing: 58) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    ZStack(alignment: .bottom) {
                        Text(tab.title)
                            .font(.headline)
                            .fontWeight(selectedTab == tab ? .bold : .semibold)
                            .foregroundStyle(selectedTab == tab ? Color.kzOnPrimaryContainer : Color.kzTextSecondary)
                            .frame(maxHeight: .infinity, alignment: .center)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(selectedTab == tab ? Color.kzOnPrimaryContainer : Color.clear)
                            .frame(width: tab.underlineWidth, height: 5)
                            .padding(.bottom, 3)
                    }
                    .frame(width: tab.controlWidth, height: 78, alignment: .center)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(tabBackgroundColor(for: tab))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(DetailTabButtonStyle())
                .focused($focusedElement, equals: .tab(tab))
            }
        }
        .frame(maxWidth: 1260, alignment: .center)
        .focusSection()
    }

    private func tabBackgroundColor(for tab: DetailTab) -> Color {
        if focusedElement == .tab(tab) {
            return Color.white.opacity(0.10)
        }

        if selectedTab == tab {
            return Color.kzSurfaceContainer.opacity(0.52)
        }

        return Color.clear
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 34) {
            if !displayedBangumi.summary.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("简介")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.kzText)

                    Text(displayedBangumi.summary)
                        .font(.system(size: 22, weight: .semibold))
                        .lineSpacing(6)
                        .foregroundStyle(Color.kzText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(focusedElement == .summary ? Color.kzSurfaceContainer.opacity(0.48) : Color.clear)
                )
                .contentShape(Rectangle())
                .focusable()
                .focused($focusedElement, equals: .summary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailContent: some View {
        HStack(alignment: .top, spacing: 0) {
            selectedDetailSection
                .frame(maxWidth: displayedBangumi.tags.isEmpty ? 1260 : 820, alignment: .leading)

            if !displayedBangumi.tags.isEmpty {
                Spacer(minLength: 96)

                tagsSidebar
                    .frame(width: rightInfoColumnWidth, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var selectedDetailSection: some View {
        switch selectedTab {
        case .overview:
            overviewSection
        case .episodes:
            episodesSection
        case .chatter:
            chatterSection
        case .characters:
            charactersSection
        case .reviews:
            reviewsSection
        case .staff:
            staffSection
        }
    }

    private var tagsSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("标签")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Color.kzText)

            FlowLayout(spacing: 8) {
                ForEach(displayedBangumi.tags, id: \.name) { tag in
                    TagChip(tag: tag)
                }
            }
        }
    }

    private var episodesSection: some View {
        Group {
            if viewModel.isPreparingPlayback && viewModel.playableEpisodes.isEmpty {
                ProgressView()
                    .tint(.kzPrimary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else if viewModel.playableEpisodes.isEmpty {
                VStack(spacing: 14) {
                    Text("暂无可用播放源")
                        .font(.headline)
                        .foregroundStyle(Color.kzText)
                    Text("没有从插件源匹配到可播放章节，可以稍后重试或从搜索页选择其它来源。")
                        .font(.subheadline)
                        .foregroundStyle(Color.kzTextSecondary)
                    Button {
                        showingSourceSheet = true
                    } label: {
                        Label("选择来源", systemImage: "play.rectangle")
                            .padding(.horizontal, 18)
                            .frame(minHeight: 52)
                    }
                    .buttonStyle(TVPillButtonStyle())
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                    ForEach(viewModel.playableEpisodes) { episode in
                        EpisodeCard(episode: episode) {
                            playEpisode(episode)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 980, alignment: .leading)
    }

    private var chatterSection: some View {
        DetailAsyncList(
            isLoading: viewModel.isLoadingComments,
            errorMessage: viewModel.commentsError,
            isEmpty: viewModel.comments.isEmpty,
            emptyTitle: "暂无吐槽"
        ) {
            LazyVStack(spacing: 14) {
                ForEach(Array(viewModel.comments.enumerated()), id: \.offset) { _, comment in
                    SubjectCommentRow(comment: comment)
                }
            }
        }
        .frame(maxWidth: 980, alignment: .leading)
    }

    private var charactersSection: some View {
        DetailAsyncList(
            isLoading: viewModel.isLoadingCharacters,
            errorMessage: viewModel.charactersError,
            isEmpty: viewModel.characters.isEmpty,
            emptyTitle: "暂无角色信息"
        ) {
            LazyVStack(spacing: 12) {
                ForEach(Array(viewModel.characters.enumerated()), id: \.offset) { _, character in
                    CharacterCreditRow(character: character)
                }
            }
        }
        .frame(maxWidth: 980, alignment: .leading)
    }

    private var reviewsSection: some View {
        VStack(spacing: 12) {
            Text("施工中")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Color.kzText)
        }
        .frame(maxWidth: 980, minHeight: 180)
    }

    private var staffSection: some View {
        DetailAsyncList(
            isLoading: viewModel.isLoadingStaff,
            errorMessage: viewModel.staffError,
            isEmpty: viewModel.staff.isEmpty,
            emptyTitle: "暂无制作人员信息"
        ) {
            LazyVStack(spacing: 12) {
                ForEach(Array(viewModel.staff.enumerated()), id: \.offset) { _, staff in
                    StaffCreditRow(staff: staff)
                }
            }
        }
        .frame(maxWidth: 980, alignment: .leading)
    }

    private func playEpisode(_ episode: Episode) {
        guard episode.pageURL?.isEmpty == false else {
            showingSourceSheet = true
            return
        }

        let isUserSelectedPlayback = showingSourceSheet
        showingSourceSheet = false
        viewModel.stopSourceSearch()
        if let session = viewModel.makePlaybackSession(
            bangumi: displayedBangumi,
            selectedEpisode: episode,
            isUserSelected: isUserSelectedPlayback
        ) {
            router.navigate(to: .playerSession(session))
        } else {
            router.navigate(to: .player(bangumi: displayedBangumi, episode: episode))
        }
    }

    private func selectSource(_ source: SearchItem) {
        Task {
            await viewModel.selectPlaybackSource(source)
        }
    }

    private func selectPluginTab(_ pluginName: String) {
        viewModel.selectSourcePluginTab(pluginName)
    }

    private func selectRoad(_ road: ChapterRoad) {
        viewModel.selectRoad(road)
    }

    private func retryPlugin(_ pluginName: String) {
        Task {
            await viewModel.searchSourcePlugin(pluginName: pluginName)
        }
    }

    private func searchAliasForPlugin(_ pluginName: String) {
        Task {
            await viewModel.searchAliasForPlugin(pluginName: pluginName, bangumi: displayedBangumi)
        }
    }

    private func manualSearchForPlugin(_ pluginName: String, keyword: String) {
        Task {
            await viewModel.searchSourcePlugin(pluginName: pluginName, keyword: keyword)
        }
    }

    private func presentCollectionMenu() {
        focusedElement = nil
        focusedCollectionStatus = nil
        lastFocusedCollectionStatus = viewModel.collectionStatus
        showingCollectionMenu = true
        scheduleCollectionMenuFocus()
    }

    private func dismissCollectionMenu() {
        showingCollectionMenu = false
        focusedCollectionStatus = nil
        lastFocusedCollectionStatus = nil
        if !showingSourceSheet {
            focusedElement = .collect
        }
    }

    private func scheduleCollectionMenuFocus(preferredStatus: CollectionStatus? = nil) {
        let defaultFocus = preferredStatus ?? viewModel.collectionStatus

        DispatchQueue.main.async {
            guard showingCollectionMenu else { return }
            focusedCollectionStatus = defaultFocus
            resetFocus(in: collectionMenuFocusScope)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard showingCollectionMenu else { return }
            focusedCollectionStatus = defaultFocus
            resetFocus(in: collectionMenuFocusScope)
        }
    }

    private func scheduleStartWatchingFocus() {
        guard !showingSourceSheet, !showingCollectionMenu else { return }

        DispatchQueue.main.async {
            guard !showingSourceSheet, !showingCollectionMenu else { return }
            focusedElement = .startWatching
        }
    }

    private func loadEpisodesForChapterTabIfNeeded() {
        guard viewModel.playableEpisodes.isEmpty, !viewModel.isSearchingSources else { return }

        Task {
            await viewModel.ensurePlayableEpisodesFromAvailableSources()
        }
    }

    private func loadTabDataIfNeeded(_ tab: DetailTab) {
        Task {
            switch tab {
            case .overview, .reviews:
                break
            case .episodes:
                await viewModel.ensurePlayableEpisodesFromAvailableSources()
            case .chatter:
                await viewModel.loadCommentsIfNeeded(bangumiID: displayedBangumi.id)
            case .characters:
                await viewModel.loadCharactersIfNeeded(bangumiID: displayedBangumi.id)
            case .staff:
                await viewModel.loadStaffIfNeeded(bangumiID: displayedBangumi.id)
            }
        }
    }
}

private enum DetailFocus: Hashable {
    case collect
    case startWatching
    case tab(DetailTab)
    case summary
}

enum CollectionStatus: Int, CaseIterable {
    case none = 0
    case watching = 1
    case wantToWatch = 2
    case onHold = 3
    case watched = 4
    case dropped = 5

    init(type: Int?) {
        self = CollectionStatus(rawValue: type ?? 0) ?? .none
    }

    var title: String {
        switch self {
        case .none: return "未追"
        case .watching: return "在看"
        case .wantToWatch: return "想看"
        case .onHold: return "搁置"
        case .watched: return "看过"
        case .dropped: return "抛弃"
        }
    }

    var iconName: String {
        switch self {
        case .none: return "heart"
        case .watching: return "heart.fill"
        case .wantToWatch: return "star.fill"
        case .onHold: return "calendar.badge.clock"
        case .watched: return "checkmark"
        case .dropped: return "heart.slash.fill"
        }
    }

    var collectionType: FavoriteRepository.CollectionType? {
        FavoriteRepository.CollectionType(rawValue: rawValue)
    }
}

private enum DetailTab: CaseIterable {
    case overview
    case episodes
    case chatter
    case characters
    case reviews
    case staff

    var title: String {
        switch self {
        case .overview: return "概览"
        case .episodes: return "章节"
        case .chatter: return "吐槽"
        case .characters: return "角色"
        case .reviews: return "评论"
        case .staff: return "制作人员"
        }
    }

    var underlineWidth: CGFloat {
        switch self {
        case .overview, .episodes, .chatter, .characters, .reviews:
            return 72
        case .staff:
            return 138
        }
    }

    var controlWidth: CGFloat {
        switch self {
        case .overview, .episodes, .chatter, .characters, .reviews:
            return 120
        case .staff:
            return 176
        }
    }
}

private struct KazumiMetricBlock: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.kzText)

            Text(value)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Color.kzPrimary.opacity(0.78))
                .lineLimit(1)
        }
    }
}

private struct StarRating: View {
    let score: Double

    private var rating: Double {
        max(0, min(score / 2.0, 5.0))
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: starName(for: index))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.kzPrimary.opacity(indexValue(index) <= rating + 0.5 ? 0.78 : 0.32))
            }
        }
    }

    private func starName(for index: Int) -> String {
        let value = Double(index) + 1
        if rating >= value {
            return "star.fill"
        }
        if rating >= value - 0.5 {
            return "star.leadinghalf.filled"
        }
        return "star.fill"
    }

    private func indexValue(_ index: Int) -> Double {
        Double(index) + 1
    }
}

private struct RatingHistogram: View {
    let votesCount: [Int]
    private let barWidth: CGFloat = 28
    private let columnWidth: CGFloat = 38
    private let columnSpacing: CGFloat = 10

    private var normalizedVotes: [Int] {
        Array(votesCount.prefix(10))
    }

    private var maxVote: Int {
        max(normalizedVotes.max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("评分透视:")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.kzText)

            HStack(alignment: .bottom, spacing: columnSpacing) {
                ForEach(Array(normalizedVotes.enumerated()), id: \.offset) { index, count in
                    VStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.kzTextSecondary.opacity(0.58))
                            .frame(width: barWidth, height: barHeight(for: count))
                            .frame(height: 165, alignment: .bottom)

                        Text("\(index + 1)")
                            .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.kzText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .frame(width: columnWidth)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func barHeight(for count: Int) -> CGFloat {
        let minimum: CGFloat = 8
        let maximum: CGFloat = 165
        guard maxVote > 0 else { return minimum }
        let ratio = CGFloat(count) / CGFloat(maxVote)
        return max(minimum, maximum * ratio)
    }
}

private struct TagChip: View {
    let tag: BangumiTag

    var body: some View {
        HStack(spacing: 6) {
            Text(tag.name)
                .foregroundStyle(Color.kzText)

            if tag.count > 0 {
                Text("\(tag.count)")
                    .foregroundStyle(Color.kzOnPrimaryContainer)
            }
        }
        .font(.system(size: 24, weight: .semibold))
        .padding(.horizontal, 12)
        .frame(minHeight: 38)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.kzTextSecondary.opacity(0.34), lineWidth: 1)
        )
    }
}

private struct HeroActionButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Capsule()
                    .fill(backgroundColor)
            )
            .shadow(
                color: isFocused ? Color.kzFocusGlow : Color.clear,
                radius: isFocused ? 18 : 0,
                x: 0,
                y: isFocused ? 8 : 0
            )
            .scaleEffect(isFocused ? 1.055 : 1.0)
            .opacity(configuration.isPressed ? 0.76 : 1)
            .animation(.easeOut(duration: 0.16), value: isFocused)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var backgroundColor: Color {
        if isFocused {
            return isPrimary ? Color.kzPrimaryContainer.opacity(0.92) : Color.kzPrimary.opacity(0.28)
        }

        return Color.kzSurfaceContainer.opacity(0.78)
    }

}

struct EpisodeCard: View {
    let episode: Episode
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(episode.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.kzText)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !episode.airDate.isEmpty {
                    Text(episode.airDate)
                        .font(.caption)
                        .foregroundStyle(Color.kzTextSecondary)
                        .lineLimit(1)
                }
            }
            .frame(minHeight: 72, alignment: .topLeading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.kzSurfaceContainerLow)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(TVCardButtonStyle())
    }
}

enum SourcePluginSearchStatus: Hashable {
    case pending
    case success
    case noResult
    case captcha
    case error(String)

    var sortPriority: Int {
        switch self {
        case .success:
            return 0
        case .pending:
            return 1
        case .captcha:
            return 2
        case .error:
            return 3
        case .noResult:
            return 4
        }
    }

    var indicatorColor: Color {
        switch self {
        case .pending:
            return Color.kzTextSecondary.opacity(0.7)
        case .success:
            return Color.kzPrimary
        case .noResult:
            return Color.orange
        case .captcha:
            return Color.blue
        case .error:
            return Color.red
        }
    }
}

struct SourcePluginTab: Identifiable, Hashable {
    let plugin: PluginRule
    var status: SourcePluginSearchStatus
    var keyword: String
    var results: [SearchItem]

    var id: String { plugin.name }
}

private struct PluginSourceSearchResult {
    let plugin: PluginRule
    let keyword: String
    let results: [SearchItem]
    let errorDescription: String?
    let isCaptcha: Bool
}

private struct SourcePluginSearchTimeoutError: LocalizedError {
    let pluginName: String

    var errorDescription: String? {
        "\(pluginName) 搜索超时"
    }
}

private final class SourcePluginSearchRaceBox {
    private let lock = NSLock()
    private var didResume = false

    func resume(
        _ continuation: CheckedContinuation<Result<[SearchItem], Error>, Never>,
        with result: Result<[SearchItem], Error>
    ) {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        lock.unlock()
        continuation.resume(returning: result)
    }
}

private enum SourceSheetFocus: Hashable {
    case plugin(String)
    case source(String)
    case road(String)
    case episode(Int)
    case primaryAction
    case secondaryAction
    case manualSearch
    case manualCancel
}

private struct SourceSelectionSheet: View {
    @FocusState private var focusedElement: SourceSheetFocus?
    @FocusState private var isManualKeywordFocused: Bool
    @State private var showingManualSearch = false
    @State private var manualPluginName = ""
    @State private var manualKeyword = ""
    @State private var autoSelectedSourceKey: String?

    let bangumi: Bangumi
    let sourceItem: SearchItem?
    let sourcePluginTabs: [SourcePluginTab]
    let selectedPluginName: String?
    let sourceQueryKeyword: String
    let sourceCandidates: [SearchItem]
    let sourceRoads: [ChapterRoad]
    let selectedRoadID: String?
    let episodes: [Episode]
    let isLoading: Bool
    let loadingSourceKey: String?
    let sourceSelectionError: String?
    let selectPluginTab: (String) -> Void
    let selectSource: (SearchItem) -> Void
    let selectRoad: (ChapterRoad) -> Void
    let retryPlugin: (String) -> Void
    let searchAliasForPlugin: (String) -> Void
    let manualSearchForPlugin: (String, String) -> Void
    let playEpisode: (Episode) -> Void
    let dismiss: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color.kzTextSecondary.opacity(0.86))
                        .frame(width: 48, height: 6)
                        .padding(.top, 24)
                        .padding(.bottom, 22)

                    headerTabs

                    Rectangle()
                        .fill(Color.kzTextSecondary.opacity(0.18))
                        .frame(height: 1)

                    selectedPluginContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(
                    width: min(proxy.size.width * 0.58, 1120),
                    height: min(proxy.size.height * 0.75, 780)
                )
                .background(Color.kzBackground)
                .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                .shadow(color: Color.black.opacity(0.46), radius: 28, x: 0, y: 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                if showingManualSearch {
                    manualSearchOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
        }
        .animation(.easeOut(duration: 0.16), value: showingManualSearch)
        .onAppear {
            scheduleDefaultFocus()
        }
        .onChange(of: selectedPluginName) { _, _ in
            scheduleDefaultFocus()
        }
        .onChange(of: sourcePluginTabs) { _, _ in
            guard focusedElement == nil, !showingManualSearch else { return }
            scheduleDefaultFocus()
        }
        .onChange(of: sourceRoads) { _, _ in
            guard !showingManualSearch else { return }
            scheduleDefaultFocus()
        }
        .onChange(of: showingManualSearch) { _, isShowing in
            guard isShowing else { return }
            focusedElement = nil
            DispatchQueue.main.async {
                isManualKeywordFocused = true
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            autoSelectSingleSourceIfNeeded()
        }
        .onChange(of: selectedPluginName) { _, _ in
            autoSelectSingleSourceIfNeeded()
        }
        .onChange(of: sourcePluginTabs) { _, _ in
            autoSelectSingleSourceIfNeeded()
        }
    }

    private var selectedTab: SourcePluginTab? {
        if let selectedPluginName,
           let tab = orderedSourcePluginTabs.first(where: { $0.plugin.name == selectedPluginName }) {
            return tab
        }

        return orderedSourcePluginTabs.first
    }

    private var orderedSourcePluginTabs: [SourcePluginTab] {
        SourcePlaybackPreferenceStore.shared.sortedPluginTabs(sourcePluginTabs)
    }

    private var headerTabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 42) {
                ForEach(orderedSourcePluginTabs) { tab in
                    pluginTabButton(tab)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .frame(height: 96)
    }

    private var selectedPluginContent: some View {
        Group {
            if sourcePluginTabs.isEmpty {
                loadingState("正在加载规则")
            } else if let tab = selectedTab {
                switch tab.status {
                case .pending:
                    loadingState("\(tab.plugin.name) 正在搜索")
                case .success:
                    sourceResults(tab)
                case .noResult:
                    emptyState(
                        "\(tab.plugin.name) 无结果 使用别名或左右滑动以切换到其他视频来源",
                        primaryTitle: "别名检索",
                        secondaryTitle: "手动检索",
                        primaryAction: { searchAliasForPlugin(tab.plugin.name) },
                        secondaryAction: { presentManualSearch(for: tab.plugin.name) }
                    )
                case .captcha:
                    emptyState(
                        "\(tab.plugin.name) 需要验证码验证",
                        primaryTitle: "别名检索",
                        secondaryTitle: "手动检索",
                        primaryAction: { searchAliasForPlugin(tab.plugin.name) },
                        secondaryAction: { presentManualSearch(for: tab.plugin.name) }
                    )
                case .error(let message):
                    emptyState(
                        message.isEmpty ? "\(tab.plugin.name) 搜索失败" : message,
                        primaryTitle: "重试",
                        secondaryTitle: "别名检索",
                        primaryAction: { retryPlugin(tab.plugin.name) },
                        secondaryAction: { searchAliasForPlugin(tab.plugin.name) }
                    )
                }
            }
        }
    }

    private func pluginTabButton(_ tab: SourcePluginTab) -> some View {
        let isSelected = tab.plugin.name == selectedTab?.plugin.name

        return Button {
            selectPluginTab(tab.plugin.name)
        } label: {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Text(tab.plugin.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(isSelected ? Color.kzText : Color.kzTextSecondary)
                        .lineLimit(1)

                    if SourcePlaybackPreferenceStore.shared.supportsNativeLoopbackPlayback(tab.plugin.name) {
                        nativePlaybackBadge(title: "本机")
                    }

                    Circle()
                        .fill(tab.status.indicatorColor)
                        .frame(width: 10, height: 10)
                }

                RoundedRectangle(cornerRadius: 3)
                    .fill(isSelected ? Color.kzOnPrimaryContainer.opacity(0.78) : Color.clear)
                    .frame(width: 84, height: 5)
            }
            .frame(height: 66)
            .contentShape(Rectangle())
        }
        .buttonStyle(SourceTabButtonStyle())
        .focused($focusedElement, equals: .plugin(tab.plugin.name))
    }

    private func sourceResults(_ tab: SourcePluginTab) -> some View {
        let results = uniqueResults(tab.results)

        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if shouldShowSourceButtons(tab, results: results) {
                    LazyVStack(spacing: 14) {
                        ForEach(results) { source in
                            sourceButton(source)
                        }
                    }
                }

                if sourceBelongsToSelectedTab(tab), !sourceRoads.isEmpty {
                    manualEpisodePicker
                } else if let sourceSelectionError, !sourceSelectionError.isEmpty {
                    Text(sourceSelectionError)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.kzTextSecondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
    }

    private func sourceButton(_ source: SearchItem) -> some View {
        let sourceID = sourceKey(source)
        let isSelected = sourceItem.map { sourceKey($0) == sourceID } ?? false

        return Button {
            selectSource(source)
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(source.displayName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.kzText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                }

                Spacer(minLength: 16)

                if SourcePlaybackPreferenceStore.shared.supportsNativeLoopbackPlayback(source.pluginName) {
                    nativePlaybackBadge(title: "本机播放")
                }

                if loadingSourceKey == sourceID {
                    ProgressView()
                        .tint(.kzPrimary)
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .background(isSelected ? Color.kzPrimaryContainer.opacity(0.34) : Color.kzSurfaceContainerLow)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(TVCardButtonStyle())
        .focused($focusedElement, equals: .source(sourceID))
    }

    private func nativePlaybackBadge(title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(Color.kzOnPrimaryContainer)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.kzPrimaryContainer.opacity(0.72))
            )
    }

    private var manualEpisodePicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("线路")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.kzText)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(sourceRoads) { road in
                        let isSelected = road.id == selectedRoadID
                        Button {
                            selectRoad(road)
                        } label: {
                            Text(road.name)
                                .font(.headline)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                                .foregroundStyle(isSelected ? Color.kzOnPrimaryContainer : Color.kzTextSecondary)
                                .frame(minWidth: 128, maxWidth: 210, minHeight: 54)
                                .padding(.horizontal, 18)
                        }
                        .buttonStyle(SourceRoadButtonStyle(isSelected: isSelected))
                        .focused($focusedElement, equals: .road(road.id))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.hidden)
            .frame(height: 82)

            Text("章节")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.kzText)
                .padding(.top, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(episodes) { episode in
                    Button {
                        playEpisode(episode)
                    } label: {
                        Text(episode.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.kzText)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                            .padding(.horizontal, 12)
                            .background(Color.kzSurfaceContainerLow)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(TVCardButtonStyle())
                    .focused($focusedElement, equals: .episode(episode.id))
                }
            }
        }
        .padding(.top, 6)
    }

    private func sourceBelongsToSelectedTab(_ tab: SourcePluginTab) -> Bool {
        guard let sourceItem else { return false }
        return sourceItem.pluginName == tab.plugin.name
    }

    private func shouldShowSourceButtons(_ tab: SourcePluginTab, results: [SearchItem]) -> Bool {
        guard results.count == 1,
              let onlyResult = results.first,
              let sourceItem,
              sourceKey(sourceItem) == sourceKey(onlyResult),
              !sourceRoads.isEmpty,
              sourceItem.pluginName == tab.plugin.name else {
            return true
        }

        return false
    }

    private func loadingState(_ title: String) -> some View {
        VStack(spacing: 18) {
            ProgressView()
                .tint(.kzPrimary)
                .scaleEffect(1.25)

            Text(title)
                .font(.headline)
                .foregroundStyle(Color.kzText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyState(
        _ title: String,
        primaryTitle: String,
        secondaryTitle: String,
        primaryAction: @escaping () -> Void,
        secondaryAction: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 24) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Color.kzText)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button(primaryTitle, action: primaryAction)
                    .font(.headline)
                    .foregroundStyle(Color.kzOnPrimaryContainer)
                    .padding(.horizontal, 26)
                    .frame(minHeight: 58)
                    .background(Capsule().fill(Color.kzPrimaryContainer.opacity(0.74)))
                    .buttonStyle(TVPillButtonStyle())
                    .focused($focusedElement, equals: .primaryAction)

                Button(secondaryTitle, action: secondaryAction)
                    .font(.headline)
                    .foregroundStyle(Color.kzOnPrimaryContainer)
                    .padding(.horizontal, 26)
                    .frame(minHeight: 58)
                    .background(Capsule().fill(Color.kzSurfaceContainer))
                    .buttonStyle(TVPillButtonStyle())
                    .focused($focusedElement, equals: .secondaryAction)
            }
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var manualSearchOverlay: some View {
        ZStack {
            Color.black.opacity(0.48)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text("手动检索")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.kzText)

                Text(manualPluginName)
                    .font(.headline)
                    .foregroundStyle(Color.kzPrimary)

                TextField("输入关键词", text: $manualKeyword)
                    .font(.headline)
                    .foregroundStyle(Color.kzText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 18)
                    .frame(height: 64)
                    .background(Color.kzSurfaceContainerLow)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .focusable()
                    .focused($isManualKeywordFocused)
                    .onSubmit {
                        submitManualSearch()
                    }

                HStack(spacing: 14) {
                    Button("搜索") {
                        submitManualSearch()
                    }
                    .font(.headline)
                    .foregroundStyle(Color.kzOnPrimaryContainer)
                    .padding(.horizontal, 24)
                    .frame(minHeight: 56)
                    .background(Capsule().fill(Color.kzPrimaryContainer.opacity(0.86)))
                    .buttonStyle(TVPillButtonStyle())
                    .focused($focusedElement, equals: .manualSearch)

                    Button("取消") {
                        showingManualSearch = false
                    }
                    .font(.headline)
                    .foregroundStyle(Color.kzTextSecondary)
                    .padding(.horizontal, 24)
                    .frame(minHeight: 56)
                    .background(Capsule().fill(Color.kzSurfaceContainer))
                    .buttonStyle(TVPillButtonStyle())
                    .focused($focusedElement, equals: .manualCancel)
                }
            }
            .padding(30)
            .frame(width: 520, alignment: .leading)
            .background(Color.kzBackground)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: Color.black.opacity(0.48), radius: 24, x: 0, y: 14)
        }
    }

    private func presentManualSearch(for pluginName: String) {
        manualPluginName = pluginName
        manualKeyword = selectedTab?.keyword.isEmpty == false ? selectedTab?.keyword ?? sourceQueryKeyword : sourceQueryKeyword
        showingManualSearch = true
    }

    private func submitManualSearch() {
        let keyword = manualKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !manualPluginName.isEmpty, !keyword.isEmpty else { return }
        showingManualSearch = false
        manualSearchForPlugin(manualPluginName, keyword)
    }

    private func autoSelectSingleSourceIfNeeded() {
        guard !showingManualSearch,
              loadingSourceKey == nil,
              let tab = selectedTab,
              case .success = tab.status else {
            return
        }

        let results = uniqueResults(tab.results)
        guard results.count == 1, let source = results.first else { return }

        let key = sourceKey(source)
        if sourceItem.map({ sourceKey($0) == key }) == true {
            autoSelectedSourceKey = key
            return
        }

        guard autoSelectedSourceKey != key else { return }
        autoSelectedSourceKey = key
        selectSource(source)
    }

    private func uniqueResults(_ results: [SearchItem]) -> [SearchItem] {
        var seen = Set<String>()
        var unique: [SearchItem] = []

        for result in results {
            let key = sourceKey(result)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(result)
        }

        return unique
    }

    private func sourceKey(_ source: SearchItem) -> String {
        "\(source.pluginName)|\(source.src)"
    }

    private func scheduleDefaultFocus() {
        DispatchQueue.main.async {
            focusedElement = defaultFocus
        }
    }

    private var defaultFocus: SourceSheetFocus? {
        guard let selectedTab else {
            return nil
        }

        if sourceBelongsToSelectedTab(selectedTab), !sourceRoads.isEmpty {
            return .road(selectedRoadID ?? sourceRoads[0].id)
        }

        if case .success = selectedTab.status,
           let firstResult = uniqueResults(selectedTab.results).first {
            return .source(sourceKey(firstResult))
        }

        return .plugin(selectedTab.plugin.name)
    }
}

private struct SourceTabButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isFocused ? Color.white.opacity(0.08) : Color.clear)
            )
            .scaleEffect(isFocused ? 1.04 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.14), value: isFocused)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct SourceRoadButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Capsule()
                    .fill(backgroundColor)
            )
            .overlay {
                Capsule()
                    .stroke(
                        isFocused ? Color.kzPrimary.opacity(0.82) : Color.clear,
                        lineWidth: 2
                    )
            }
            .shadow(
                color: isFocused ? Color.kzFocusGlow : Color.clear,
                radius: isFocused ? 12 : 0,
                x: 0,
                y: isFocused ? 5 : 0
            )
            .scaleEffect(isFocused ? 1.035 : 1.0)
            .zIndex(isFocused ? 10 : 0)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: 0.16), value: isFocused)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var backgroundColor: Color {
        if isFocused {
            return isSelected ? Color.kzPrimaryContainer.opacity(0.96) : Color.kzFocusFill
        }

        return isSelected ? Color.kzPrimaryContainer.opacity(0.74) : Color.kzSurfaceContainerLow
    }
}

private struct DetailTabButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isFocused ? 1.035 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.14), value: isFocused)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct CollectionMenuButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isFocused ? Color.kzPrimaryContainer.opacity(0.72) : Color.clear)
            )
            .scaleEffect(isFocused ? 1.025 : 1.0)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.14), value: isFocused)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct DetailAsyncList<Content: View>: View {
    let isLoading: Bool
    let errorMessage: String?
    let isEmpty: Bool
    let emptyTitle: String
    @ViewBuilder let content: Content

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(.kzPrimary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Text("获取失败")
                        .font(.headline)
                        .foregroundStyle(Color.kzText)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(Color.kzTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else if isEmpty {
                Text(emptyTitle)
                    .font(.headline)
                    .foregroundStyle(Color.kzTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                content
            }
        }
    }
}

private struct SubjectCommentRow: View {
    let comment: BangumiSubjectComment
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(comment.userName)
                    .font(.headline)
                    .foregroundStyle(Color.kzText)

                Spacer()

                if !comment.createdAt.isEmpty {
                    Text(comment.createdAt)
                        .font(.caption)
                        .foregroundStyle(Color.kzTextSecondary)
                }
            }

            Text(comment.content)
                .font(.body)
                .foregroundStyle(Color.kzTextSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isFocused ? Color.kzSurfaceContainer.opacity(0.94) : Color.kzSurfaceContainerLow.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .scaleEffect(isFocused ? 1.015 : 1.0)
        .focusable()
        .animation(.easeOut(duration: 0.14), value: isFocused)
    }
}

private struct CharacterCreditRow: View {
    let character: BangumiCharacterCredit
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 14) {
            CreditImage(urlString: character.image)

            VStack(alignment: .leading, spacing: 5) {
                Text(character.displayName)
                    .font(.headline)
                    .foregroundStyle(Color.kzText)

                if !character.name.isEmpty, character.name != character.displayName {
                    Text(character.name)
                        .font(.subheadline)
                        .foregroundStyle(Color.kzTextSecondary)
                }

                HStack(spacing: 12) {
                    if !character.relation.isEmpty {
                        Text(character.relation)
                    }
                    if !character.actorName.isEmpty {
                        Text(character.actorName)
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.kzPrimary.opacity(0.82))
            }

            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isFocused ? Color.kzSurfaceContainer.opacity(0.94) : Color.kzSurfaceContainerLow.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .scaleEffect(isFocused ? 1.015 : 1.0)
        .focusable()
        .animation(.easeOut(duration: 0.14), value: isFocused)
    }
}

private struct StaffCreditRow: View {
    let staff: BangumiStaffCredit
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 14) {
            CreditImage(urlString: staff.image)

            VStack(alignment: .leading, spacing: 6) {
                Text(staff.displayName)
                    .font(.headline)
                    .foregroundStyle(Color.kzText)

                if !staff.name.isEmpty, staff.name != staff.displayName {
                    Text(staff.name)
                        .font(.subheadline)
                        .foregroundStyle(Color.kzTextSecondary)
                }

                if !staff.jobs.isEmpty {
                    Text(staff.jobs.joined(separator: " / "))
                        .font(.caption)
                        .foregroundStyle(Color.kzPrimary.opacity(0.82))
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isFocused ? Color.kzSurfaceContainer.opacity(0.94) : Color.kzSurfaceContainerLow.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .scaleEffect(isFocused ? 1.015 : 1.0)
        .focusable()
        .animation(.easeOut(duration: 0.14), value: isFocused)
    }
}

private struct CreditImage: View {
    let urlString: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.kzCardBackground)

            if let url = normalizedURL {
                KFImage(url)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "person")
                    .font(.title3)
                    .foregroundStyle(Color.kzTextSecondary)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var normalizedURL: URL? {
        var value = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("//") {
            value = "https:" + value
        } else if value.hasPrefix("http://") {
            value = "https://" + value.dropFirst("http://".count)
        }
        return URL(string: value)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y),
                proposal: .unspecified
            )
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}

final class SourcePlaybackPreferenceStore {
    static let shared = SourcePlaybackPreferenceStore()

    private let defaults = UserDefaults.standard
    private let storageKey = "kazumi.sourcePlaybackPreferences.v1"
    private let nativeLoopbackPlaybackPlugins: Set<String> = [
        "mxdm",
        "omofun03",
        "baimao",
        "enlie",
        "gpjda",
        "aafun",
    ]
    private let nativeOnlyPluginPriority: [String: Double] = [
        "MXdm": 10_000,
        "omofun03": 9_900,
        "baimao": 9_800,
        "enlie": 9_700,
        "gpjda": 9_600,
        "aafun": 9_500,
        "mwcy": 7,
        "gugu3": 6,
        "7sefun": 5,
        "yishijie": 4,
        "DM84": 3,
        "AGE": 2,
        "xfdmneo": 1,
    ]
    private var records: [String: SourcePlaybackPreferenceRecord]

    private init() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: SourcePlaybackPreferenceRecord].self, from: data) {
            records = decoded
        } else {
            records = [:]
        }
    }

    func sortedSources(_ sources: [SearchItem]) -> [SearchItem] {
        sources.sorted { lhs, rhs in
            let lhsScore = pluginScore(lhs.pluginName)
            let rhsScore = pluginScore(rhs.pluginName)
            if lhsScore == rhsScore {
                return lhs.pluginName < rhs.pluginName
            }
            return lhsScore > rhsScore
        }
    }

    func sortedPluginTabs(_ tabs: [SourcePluginTab]) -> [SourcePluginTab] {
        tabs.enumerated()
            .sorted { lhs, rhs in
                if !SettingsRepository.shared.serverProxyEnabled {
                    let lhsRank = nativeOnlyTabRank(lhs.element)
                    let rhsRank = nativeOnlyTabRank(rhs.element)
                    if lhsRank != rhsRank {
                        return lhsRank < rhsRank
                    }
                }

                let lhsScore = pluginScore(lhs.element.plugin.name)
                let rhsScore = pluginScore(rhs.element.plugin.name)

                let lhsStatusPriority = lhs.element.status.sortPriority
                let rhsStatusPriority = rhs.element.status.sortPriority
                if lhsStatusPriority != rhsStatusPriority {
                    return lhsStatusPriority < rhsStatusPriority
                }

                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }

                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    func preferredPluginName(in tabs: [SourcePluginTab]) -> String? {
        sortedPluginTabs(tabs).first?.plugin.name
    }

    func preferredSuccessfulPluginName(in tabs: [SourcePluginTab]) -> String? {
        let orderedTabs = sortedPluginTabs(tabs)
        if !SettingsRepository.shared.serverProxyEnabled {
            return orderedTabs.first { tab in
                supportsNativeLoopbackPlayback(tab.plugin.name) && tabHasSearchResults(tab)
            }?.plugin.name
        }

        return orderedTabs.first(where: tabHasSearchResults)?.plugin.name
    }

    func supportsNativeLoopbackPlayback(_ pluginName: String) -> Bool {
        nativeLoopbackPlaybackPlugins.contains(pluginName.lowercased())
    }

    private func nativeOnlyTabRank(_ tab: SourcePluginTab) -> Int {
        let isNative = supportsNativeLoopbackPlayback(tab.plugin.name)
        let hasSearchResults = tabHasSearchResults(tab)
        let isPending = tabIsPending(tab)

        if isNative && hasSearchResults { return 0 }
        if isNative && isPending { return 1 }
        if isNative { return 2 }
        if hasSearchResults { return 3 }
        if isPending { return 4 }
        return 5
    }

    private func tabHasSearchResults(_ tab: SourcePluginTab) -> Bool {
        if case .success = tab.status {
            return !tab.results.isEmpty
        }
        return false
    }

    private func tabIsPending(_ tab: SourcePluginTab) -> Bool {
        if case .pending = tab.status {
            return true
        }
        return false
    }

    func preferredRoad(in roads: [ChapterRoad], pluginName: String) -> ChapterRoad? {
        let matches = roads.map { road in
            (road, roadScore(pluginName: pluginName, roadID: road.id, roadName: road.name))
        }

        let sorted = matches.sorted { lhs, rhs in
            if lhs.1 == rhs.1 {
                return lhs.0.episodes.count > rhs.0.episodes.count
            }
            return lhs.1 > rhs.1
        }

        guard sorted.contains(where: { $0.1 != 0 }) else {
            return nil
        }

        return sorted.first?.0
    }

    func recordSuccess(pluginName: String, roadID: String, roadName: String, episodeCount: Int, isUserSelected: Bool) {
        let key = recordKey(pluginName: pluginName, roadID: roadID, roadName: roadName)
        var record = records[key] ?? SourcePlaybackPreferenceRecord(pluginName: pluginName, roadID: roadID, roadName: roadName)
        record.successCount += 1
        record.lastEpisodeCount = max(record.lastEpisodeCount, episodeCount)
        record.lastUsedAt = Date().timeIntervalSince1970
        if isUserSelected {
            record.userSelectedCount += 1
        }
        records[key] = record
        save()
    }

    func recordFailure(pluginName: String) {
        let keys = records.keys.filter { key in
            records[key]?.pluginName == pluginName
        }

        for key in keys {
            records[key]?.failureCount += 1
        }
        save()
    }

    func recordFailure(pluginName: String, roadID: String, roadName: String, episodeCount: Int) {
        let key = recordKey(pluginName: pluginName, roadID: roadID, roadName: roadName)
        var record = records[key] ?? SourcePlaybackPreferenceRecord(pluginName: pluginName, roadID: roadID, roadName: roadName)
        record.failureCount += 1
        record.lastEpisodeCount = max(record.lastEpisodeCount, episodeCount)
        record.lastUsedAt = Date().timeIntervalSince1970
        records[key] = record
        save()
    }

    private func pluginScore(_ pluginName: String) -> Double {
        let learnedScore = records.values
            .filter { $0.pluginName == pluginName }
            .map(recordScore)
            .max() ?? 0
        let nativeOnlyPriority = SettingsRepository.shared.serverProxyEnabled
            ? 0
            : (nativeOnlyPluginPriority[pluginName] ?? 0)
        return nativeOnlyPriority + learnedScore
    }

    private func roadScore(pluginName: String, roadID: String, roadName: String) -> Double {
        records[recordKey(pluginName: pluginName, roadID: roadID, roadName: roadName)].map(recordScore) ?? 0
    }

    private func recordScore(_ record: SourcePlaybackPreferenceRecord) -> Double {
        let recency = max(0, 1_000_000 - (Date().timeIntervalSince1970 - record.lastUsedAt)) / 1_000_000
        let qualityProxy = min(Double(record.lastEpisodeCount), 200) / 200
        return Double(record.successCount * 3 + record.userSelectedCount * 5 - record.failureCount * 4)
            + qualityProxy
            + recency
    }

    private func recordKey(pluginName: String, roadID: String, roadName: String) -> String {
        "\(pluginName)|\(roadID)|\(roadName)"
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

private struct SourcePlaybackPreferenceRecord: Codable {
    let pluginName: String
    let roadID: String
    let roadName: String
    var successCount = 0
    var failureCount = 0
    var userSelectedCount = 0
    var lastEpisodeCount = 0
    var lastUsedAt = Date().timeIntervalSince1970
}

@MainActor
class BangumiDetailViewModel: ObservableObject {
    @Published var fullBangumi: Bangumi?
    @Published var episodes: [Episode] = []
    @Published var pluginEpisodes: [Episode] = []
    @Published var sourceRoads: [ChapterRoad] = []
    @Published var selectedRoadID: String?
    @Published var playbackSource: SearchItem?
    @Published var sourceCandidates: [SearchItem] = []
    @Published var sourcePluginTabs: [SourcePluginTab] = []
    @Published var selectedSourcePluginName: String?
    @Published var sourceQueryKeyword = ""
    @Published var loadingSourceKey: String?
    @Published var sourceSelectionError: String?
    @Published var isLoadingEpisodes = false
    @Published var isSearchingSources = false
    @Published var isResolvingPlaybackSource = false
    @Published var isCollected = false
    @Published var collectionStatus: CollectionStatus = .none
    @Published var comments: [BangumiSubjectComment] = []
    @Published var characters: [BangumiCharacterCredit] = []
    @Published var staff: [BangumiStaffCredit] = []
    @Published var isLoadingComments = false
    @Published var isLoadingCharacters = false
    @Published var isLoadingStaff = false
    @Published var commentsError: String?
    @Published var charactersError: String?
    @Published var staffError: String?
    @Published var error: Error?
    private var currentBangumiID = 0
    private var sourceSearchBangumi: Bangumi?
    private var userSelectedRoadID: String?
    private var sourceSearchTask: Task<Void, Never>?

    var playableEpisodes: [Episode] {
        pluginEpisodes.filter { episode in
            guard let pageURL = episode.pageURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !pageURL.isEmpty else {
                return false
            }
            return true
        }
    }

    var isPreparingPlayback: Bool {
        isLoadingEpisodes || isSearchingSources || isResolvingPlaybackSource
    }

    private let bangumiAPI = BangumiAPI.shared
    private let pluginManager = PluginManager.shared
    private let favoriteRepository = FavoriteRepository.shared
    private let sourcePluginSearchTimeoutNanoseconds: UInt64 = 12_000_000_000

    func loadData(bangumi: Bangumi, searchItem: SearchItem?) async {
        currentBangumiID = bangumi.id
        await loadCollectionState(bangumiId: bangumi.id)
        await loadBangumiInfoIfNeeded(bangumi: bangumi)
        await loadEpisodes(bangumiId: bangumi.id)
        sourceSearchBangumi = fullBangumi ?? bangumi

        if let searchItem {
            appendSourceCandidate(searchItem)
        }

        startSourcePluginSearch(for: fullBangumi ?? bangumi, preferredSearchItem: searchItem)
    }

    func loadCommentsIfNeeded(bangumiID: Int) async {
        guard comments.isEmpty, !isLoadingComments else { return }

        isLoadingComments = true
        commentsError = nil
        defer { isLoadingComments = false }

        do {
            comments = try await bangumiAPI.getSubjectComments(id: bangumiID)
        } catch {
            commentsError = error.localizedDescription
        }
    }

    func loadCharactersIfNeeded(bangumiID: Int) async {
        guard characters.isEmpty, !isLoadingCharacters else { return }

        isLoadingCharacters = true
        charactersError = nil
        defer { isLoadingCharacters = false }

        do {
            characters = try await bangumiAPI.getSubjectCharacters(id: bangumiID)
        } catch {
            charactersError = error.localizedDescription
        }
    }

    func loadStaffIfNeeded(bangumiID: Int) async {
        guard staff.isEmpty, !isLoadingStaff else { return }

        isLoadingStaff = true
        staffError = nil
        defer { isLoadingStaff = false }

        do {
            staff = try await bangumiAPI.getSubjectStaff(id: bangumiID)
        } catch {
            staffError = error.localizedDescription
        }
    }

    func toggleCollect(bangumi: Bangumi) async {
        await setCollectionStatus(isCollected ? .none : .watching, bangumi: bangumi)
    }

    func setCollectionStatus(_ status: CollectionStatus, bangumi: Bangumi) async {
        do {
            if let collectionType = status.collectionType {
                try await favoriteRepository.addToCollection(bangumi: bangumi, type: collectionType)
            } else {
                try await favoriteRepository.removeFromCollection(bangumiId: bangumi.id)
            }

            collectionStatus = status
            isCollected = status != .none
        } catch {
            self.error = error
            print("Failed to update collection: \(error)")
        }
    }

    func selectPlaybackSource(_ source: SearchItem) async {
        print("BangumiDetailViewModel: selected source \(source.pluginName) \(source.name) \(source.src)")
        let loadingKey = sourceKey(source)
        loadingSourceKey = loadingKey
        defer {
            if loadingSourceKey == loadingKey {
                loadingSourceKey = nil
            }
        }

        sourceSearchTask?.cancel()
        sourceSearchTask = nil
        isSearchingSources = false
        appendSourceCandidate(source)
        playbackSource = source
        sourceSelectionError = nil
        pluginEpisodes = []
        sourceRoads = []
        selectedRoadID = nil
        userSelectedRoadID = nil
        if await loadChaptersFromPlugin(searchItem: source) {
            sourceSelectionError = nil
        } else {
            sourceSelectionError = "该来源暂时没有解析到章节，请尝试列表里的其它来源。"
        }
    }

    func selectSourcePluginTab(_ pluginName: String) {
        selectedSourcePluginName = pluginName
    }

    func stopSourceSearch() {
        sourceSearchTask?.cancel()
        sourceSearchTask = nil
        isSearchingSources = false
    }

    func ensurePlayableEpisodesFromAvailableSources() async {
        guard playableEpisodes.isEmpty else { return }
        guard !isResolvingPlaybackSource else { return }

        let candidates = automaticPlaybackCandidates()
        guard !candidates.isEmpty else {
            sourceSelectionError = "暂无可用播放源"
            return
        }

        isResolvingPlaybackSource = true
        defer { isResolvingPlaybackSource = false }

        for candidate in candidates.prefix(6) {
            if await loadChaptersFromPlugin(searchItem: candidate) {
                sourceSelectionError = nil
                return
            }
        }

        sourceSelectionError = "没有从插件源匹配到可播放章节，可以从来源面板手动选择其它来源。"
    }

    func searchSourcePlugin(pluginName: String) async {
        await searchSourcePlugin(pluginName: pluginName, keyword: sourceQueryKeyword)
    }

    func searchSourcePlugin(pluginName: String, keyword: String) async {
        do {
            try await pluginManager.loadPlugins()
            guard let plugin = await pluginManager.getPlugin(name: pluginName) else {
                return
            }

            selectedSourcePluginName = pluginName
            await searchSourcePlugin(plugin: plugin, keyword: keyword, updatesGlobalLoading: true)
        } catch {
            setSourcePluginTab(pluginName: pluginName) { tab in
                tab.status = .error(error.localizedDescription)
                tab.results = []
            }
        }
    }

    func searchAliasForPlugin(pluginName: String, bangumi: Bangumi) async {
        let aliases = sourceSearchKeywords(for: bangumi).filter { $0 != sourceQueryKeyword }
        guard let alias = aliases.first else {
            await searchSourcePlugin(pluginName: pluginName)
            return
        }

        do {
            try await pluginManager.loadPlugins()
            guard let plugin = await pluginManager.getPlugin(name: pluginName) else {
                return
            }

            await searchSourcePlugin(plugin: plugin, keyword: alias, updatesGlobalLoading: true)
        } catch {
            setSourcePluginTab(pluginName: pluginName) { tab in
                tab.status = .error(error.localizedDescription)
                tab.results = []
            }
        }
    }

    func selectRoad(_ road: ChapterRoad) {
        selectedRoadID = road.id
        userSelectedRoadID = road.id
        pluginEpisodes = episodes(from: road, pluginName: playbackSource?.pluginName ?? "")
    }

    func makePlaybackSession(bangumi: Bangumi, selectedEpisode: Episode, isUserSelected: Bool = false) -> PlaybackSession? {
        guard let playbackSource, !sourceRoads.isEmpty else { return nil }

        let roads = sourceRoads.map { road in
            PlaybackRoad(
                id: road.id,
                name: road.name,
                episodes: episodes(from: road, pluginName: playbackSource.pluginName)
            )
        }

        guard roads.contains(where: { !$0.episodes.isEmpty }) else { return nil }

        let activeRoadID = selectedRoadID ?? roads.first?.id ?? ""
        let activeRoadWasUserSelected = isUserSelected && activeRoadID == userSelectedRoadID
        let fallbackSources = automaticPlaybackCandidates().filter { candidate in
            candidate.pluginName != playbackSource.pluginName || candidate.src != playbackSource.src
        }

        return PlaybackSession(
            bangumi: bangumi,
            source: playbackSource,
            candidateSources: fallbackSources,
            roads: roads,
            selectedRoadID: activeRoadID,
            selectedEpisodeID: selectedEpisode.id,
            isUserSelected: activeRoadWasUserSelected
        )
    }

    private func loadCollectionState(bangumiId: Int) async {
        do {
            if let collected = try await favoriteRepository.getCollection(bangumiId: bangumiId) {
                collectionStatus = CollectionStatus(type: collected.type)
                isCollected = true
            } else {
                collectionStatus = .none
                isCollected = false
            }
        } catch {
            print("Failed to load collection state: \(error)")
        }
    }

    private func loadBangumiInfoIfNeeded(bangumi: Bangumi) async {
        guard bangumi.summary.isEmpty || bangumi.tags.isEmpty || bangumi.votesCount.isEmpty else { return }

        do {
            fullBangumi = try await bangumiAPI.getBangumiInfo(id: bangumi.id)
        } catch {
            print("Failed to load full bangumi info: \(error)")
        }
    }

    private func loadEpisodes(bangumiId: Int) async {
        isLoadingEpisodes = true
        defer { isLoadingEpisodes = false }

        do {
            episodes = try await bangumiAPI.getEpisodes(subjectId: bangumiId)
        } catch {
            self.error = error
            print("Failed to load episodes: \(error)")
        }
    }

    @discardableResult
    private func loadChaptersFromPlugin(searchItem: SearchItem) async -> Bool {
        isResolvingPlaybackSource = true
        defer { isResolvingPlaybackSource = false }

        do {
            try await pluginManager.loadPlugins()
            guard let plugin = await pluginManager.getPlugin(name: searchItem.pluginName) else {
                print("Plugin not found: \(searchItem.pluginName)")
                return false
            }

            let chapterRoads = try await pluginManager.getChapters(pageURL: searchItem.src, plugin: plugin)
            print("BangumiDetailViewModel: \(searchItem.pluginName) \(searchItem.name) chapter roads \(chapterRoads.count), counts \(chapterRoads.map { $0.episodes.count })")

            let availableRoads = chapterRoads.filter { !$0.episodes.isEmpty }
            guard let selectedRoad = preferredRoad(from: availableRoads, pluginName: searchItem.pluginName) else {
                SourcePlaybackPreferenceStore.shared.recordFailure(pluginName: searchItem.pluginName)
                return false
            }

            sourceRoads = availableRoads
            selectedRoadID = selectedRoad.id
            userSelectedRoadID = nil
            playbackSource = searchItem
            let pluginEpisodes = episodes(from: selectedRoad, pluginName: searchItem.pluginName)

            guard !pluginEpisodes.isEmpty else { return false }
            self.pluginEpisodes = pluginEpisodes
            return true
        } catch {
            print("Failed to load chapters from plugin: \(error)")
            SourcePlaybackPreferenceStore.shared.recordFailure(pluginName: searchItem.pluginName)
            return false
        }
    }

    private func episodes(from road: ChapterRoad, pluginName: String) -> [Episode] {
        road.episodes.enumerated().map { index, item in
            Episode(
                id: -((index + 1) * 10_000 + stableEpisodeSuffix(from: "\(road.id)-\(item.src)")),
                bangumiId: currentBangumiID,
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

    private func preferredRoad(from roads: [ChapterRoad], pluginName: String) -> ChapterRoad? {
        if let preferred = SourcePlaybackPreferenceStore.shared.preferredRoad(in: roads, pluginName: pluginName) {
            return preferred
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

    private func startSourcePluginSearch(for bangumi: Bangumi, preferredSearchItem: SearchItem?) {
        sourceSearchTask?.cancel()
        sourceSearchTask = Task { [weak self] in
            await self?.queryAllSourcePlugins(for: bangumi, preferredSearchItem: preferredSearchItem)
        }
    }

    private func queryAllSourcePlugins(for bangumi: Bangumi, preferredSearchItem: SearchItem?) async {
        isSearchingSources = true
        defer { isSearchingSources = false }

        do {
            try await pluginManager.loadPlugins()
            guard !Task.isCancelled else { return }

            let plugins = await pluginManager.getAllPlugins()
            let keyword = primarySourceKeyword(for: bangumi)
            sourceQueryKeyword = keyword
            sourcePluginTabs = plugins.map { plugin in
                SourcePluginTab(
                    plugin: plugin,
                    status: .pending,
                    keyword: keyword,
                    results: []
                )
            }

            if let preferredSearchItem {
                selectedSourcePluginName = preferredSearchItem.pluginName
                mergePreferredSource(preferredSearchItem, keyword: keyword)
            } else {
                selectedSourcePluginName = SourcePlaybackPreferenceStore.shared.preferredPluginName(in: sourcePluginTabs)
            }

            await searchAllSourcePlugins(plugins: plugins, keyword: keyword)
            guard !Task.isCancelled else { return }

            if preferredSearchItem == nil || selectedTabHasNoResult() {
                let orderedTabs = SourcePlaybackPreferenceStore.shared.sortedPluginTabs(sourcePluginTabs)
                selectedSourcePluginName = SourcePlaybackPreferenceStore.shared.preferredSuccessfulPluginName(in: orderedTabs)
                    ?? orderedTabs.first?.plugin.name
            }
        } catch {
            sourceSelectionError = error.localizedDescription
            print("Failed to query source plugins: \(error)")
        }
    }

    private func searchAllSourcePlugins(plugins: [PluginRule], keyword: String) async {
        await withTaskGroup(of: PluginSourceSearchResult?.self) { group in
            for plugin in plugins {
                group.addTask { [sourcePluginSearchTimeoutNanoseconds] in
                    await Self.searchPluginResult(
                        plugin: plugin,
                        keyword: keyword,
                        timeoutNanoseconds: sourcePluginSearchTimeoutNanoseconds
                    )
                }
            }

            for await result in group {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }

                guard let result else { continue }
                applyPluginSearchResult(result)
                selectAvailableSourcePluginIfCurrentIsPending()
            }
        }
    }

    private func searchSourcePlugin(plugin: PluginRule, keyword: String, updatesGlobalLoading: Bool) async {
        if updatesGlobalLoading {
            isResolvingPlaybackSource = true
        }
        defer {
            if updatesGlobalLoading {
                isResolvingPlaybackSource = false
            }
        }

        setSourcePluginTab(pluginName: plugin.name) { tab in
            tab.status = .pending
            tab.keyword = keyword
            tab.results = []
        }

        do {
            let results = try await Self.searchPluginResultsWithTimeout(
                plugin: plugin,
                keyword: keyword,
                timeoutNanoseconds: sourcePluginSearchTimeoutNanoseconds
            )
            applyPluginSearchResult(
                PluginSourceSearchResult(
                    plugin: plugin,
                    keyword: keyword,
                    results: results,
                    errorDescription: nil,
                    isCaptcha: false
                )
            )
        } catch {
            applyPluginSearchResult(
                PluginSourceSearchResult(
                    plugin: plugin,
                    keyword: keyword,
                    results: [],
                    errorDescription: error.localizedDescription,
                    isCaptcha: plugin.antiCrawlerConfig != nil
                )
            )
            print("BangumiDetailViewModel: \(plugin.name) search failed: \(error.localizedDescription)")
        }
    }

    private static func searchPluginResult(
        plugin: PluginRule,
        keyword: String,
        timeoutNanoseconds: UInt64
    ) async -> PluginSourceSearchResult? {
        if Task.isCancelled {
            return nil
        }

        do {
            let results = try await searchPluginResultsWithTimeout(
                plugin: plugin,
                keyword: keyword,
                timeoutNanoseconds: timeoutNanoseconds
            )
            if Task.isCancelled {
                return nil
            }

            return PluginSourceSearchResult(
                plugin: plugin,
                keyword: keyword,
                results: results,
                errorDescription: nil,
                isCaptcha: false
            )
        } catch {
            if error is CancellationError || Task.isCancelled {
                return nil
            }

            return PluginSourceSearchResult(
                plugin: plugin,
                keyword: keyword,
                results: [],
                errorDescription: error.localizedDescription,
                isCaptcha: plugin.antiCrawlerConfig != nil
            )
        }
    }

    private static func searchPluginResultsWithTimeout(
        plugin: PluginRule,
        keyword: String,
        timeoutNanoseconds: UInt64
    ) async throws -> [SearchItem] {
        let result: Result<[SearchItem], Error> = await withCheckedContinuation { continuation in
            let raceBox = SourcePluginSearchRaceBox()
            let searchTask = Task {
                do {
                    let results = try await PluginManager.shared.searchWithPlugin(plugin: plugin, keyword: keyword)
                    raceBox.resume(continuation, with: .success(results))
                } catch {
                    raceBox.resume(continuation, with: .failure(error))
                }
            }

            Task {
                do {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    searchTask.cancel()
                    raceBox.resume(
                        continuation,
                        with: .failure(SourcePluginSearchTimeoutError(pluginName: plugin.name))
                    )
                } catch {
                    searchTask.cancel()
                    raceBox.resume(continuation, with: .failure(error))
                }
            }
        }
        return try result.get()
    }

    private func applyPluginSearchResult(_ result: PluginSourceSearchResult) {
        if let errorDescription = result.errorDescription {
            setSourcePluginTab(pluginName: result.plugin.name) { tab in
                tab.keyword = result.keyword
                tab.results = []
                tab.status = result.isCaptcha ? .captcha : .error(errorDescription)
            }
            return
        }

        let unique = strictSourceResults(result.results, keyword: result.keyword)
        print("BangumiDetailViewModel: \(result.plugin.name) source search raw=\(result.results.count), filtered=\(unique.count), keyword=\(result.keyword)")
        for source in unique {
            appendSourceCandidate(source)
        }

        setSourcePluginTab(pluginName: result.plugin.name) { tab in
            tab.keyword = result.keyword
            tab.results = unique
            tab.status = unique.isEmpty ? .noResult : .success
        }
    }

    private func mergePreferredSource(_ source: SearchItem, keyword: String) {
        setSourcePluginTab(pluginName: source.pluginName) { tab in
            tab.keyword = keyword
            if !tab.results.contains(where: { $0.src == source.src && $0.pluginName == source.pluginName }) {
                tab.results.insert(source, at: 0)
            }
            tab.status = .success
        }
    }

    private func setSourcePluginTab(pluginName: String, update: (inout SourcePluginTab) -> Void) {
        guard let index = sourcePluginTabs.firstIndex(where: { $0.plugin.name == pluginName }) else {
            return
        }

        update(&sourcePluginTabs[index])
    }

    private func selectAvailableSourcePluginIfCurrentIsPending() {
        guard let currentSelectedPluginName = selectedSourcePluginName,
              let selected = sourcePluginTabs.first(where: { $0.plugin.name == currentSelectedPluginName }) else {
            selectedSourcePluginName = SourcePlaybackPreferenceStore.shared.preferredSuccessfulPluginName(in: sourcePluginTabs)
            return
        }

        guard case .pending = selected.status else { return }
        selectedSourcePluginName = SourcePlaybackPreferenceStore.shared.preferredSuccessfulPluginName(in: sourcePluginTabs)
            ?? currentSelectedPluginName
    }

    private func selectedTabHasNoResult() -> Bool {
        guard let selectedSourcePluginName,
              let selected = sourcePluginTabs.first(where: { $0.plugin.name == selectedSourcePluginName }) else {
            return true
        }

        if case .success = selected.status {
            return false
        }

        return true
    }

    private func automaticPlaybackCandidates() -> [SearchItem] {
        var candidates: [SearchItem] = []

        if let playbackSource {
            candidates.append(playbackSource)
        }

        if let selectedSourcePluginName,
           let selectedTab = sourcePluginTabs.first(where: { $0.plugin.name == selectedSourcePluginName }) {
            candidates.append(contentsOf: selectedTab.results)
        }

        candidates.append(contentsOf: sourceCandidates)

        for tab in sourcePluginTabs {
            candidates.append(contentsOf: tab.results)
        }

        return SourcePlaybackPreferenceStore.shared.sortedSources(uniqueSources(candidates))
    }

    private func matchAndLoadPlayableSource(for bangumi: Bangumi) async {
        isResolvingPlaybackSource = true
        defer { isResolvingPlaybackSource = false }

        do {
            try await pluginManager.loadPlugins()

            for keyword in sourceSearchKeywords(for: bangumi) {
                let results = try await pluginManager.search(keyword: keyword)
                print("BangumiDetailViewModel: source keyword \(keyword), result count \(results.count)")
                let candidates = sourceCandidates(from: results, for: bangumi)
                for candidate in candidates {
                    appendSourceCandidate(candidate)
                    sourceSelectionError = nil
                }

                for candidate in candidates {
                    if await loadChaptersFromPlugin(searchItem: candidate) {
                        return
                    }
                }
            }
        } catch {
            print("Failed to match playable source: \(error)")
        }
    }

    private func sourceSearchKeywords(for bangumi: Bangumi) -> [String] {
        var keywords: [String] = []
        [bangumi.displayName, bangumi.name, bangumi.nameCn].forEach { keyword in
            let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !keywords.contains(trimmed) {
                keywords.append(trimmed)
            }
        }

        for alias in bangumi.alias.prefix(4) {
            let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !keywords.contains(trimmed) {
                keywords.append(trimmed)
            }
        }

        return keywords
    }

    private func primarySourceKeyword(for bangumi: Bangumi) -> String {
        let nameCn = bangumi.nameCn.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nameCn.isEmpty {
            return nameCn
        }

        let displayName = bangumi.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !displayName.isEmpty {
            return displayName
        }

        return bangumi.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sourceCandidates(from results: [SearchItem], for bangumi: Bangumi) -> [SearchItem] {
        strictSourceResults(results, bangumi: bangumi)
    }

    private func appendSourceCandidate(_ source: SearchItem) {
        guard !sourceCandidates.contains(where: { $0.src == source.src && $0.pluginName == source.pluginName }) else {
            return
        }

        sourceCandidates.append(source)
    }

    private func uniqueSources(_ results: [SearchItem]) -> [SearchItem] {
        var seen = Set<String>()
        var unique: [SearchItem] = []

        for result in results {
            let key = sourceKey(result)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(result)
        }

        return unique
    }

    private func sourceKey(_ source: SearchItem) -> String {
        "\(source.pluginName)|\(source.src)"
    }

    private func strictSourceResults(_ results: [SearchItem], keyword: String) -> [SearchItem] {
        let bangumi = sourceSearchBangumi ?? fullBangumi
        return strictSourceResults(results, bangumi: bangumi, extraKeywords: [keyword])
    }

    private func strictSourceResults(_ results: [SearchItem], bangumi: Bangumi?, extraKeywords: [String] = []) -> [SearchItem] {
        let matchKeys = strictSourceMatchKeys(for: bangumi, extraKeywords: extraKeywords)
        guard !matchKeys.isEmpty else { return [] }

        let unique = uniqueSources(results)
        let exactMatches = unique.filter { source in
            sourceStrictlyMatches(source, matchKeys: matchKeys)
        }
        if !exactMatches.isEmpty {
            return exactMatches
        }

        return unique.filter { source in
            sourceLooselyMatches(source, matchKeys: matchKeys)
        }
    }

    private func strictSourceMatchKeys(for bangumi: Bangumi?, extraKeywords: [String] = []) -> Set<String> {
        var keys = Set<String>()

        if let bangumi {
            for keyword in sourceSearchKeywords(for: bangumi) {
                let key = normalizedStrictSourceName(keyword)
                if !key.isEmpty {
                    keys.insert(key)
                }
            }
        }

        for keyword in extraKeywords {
            let key = normalizedStrictSourceName(keyword)
            if !key.isEmpty {
                keys.insert(key)
            }
        }

        return keys
    }

    private func sourceStrictlyMatches(_ source: SearchItem, matchKeys: Set<String>) -> Bool {
        [source.name, source.nameCn, source.displayName]
            .map(normalizedStrictSourceName)
            .contains { key in
                !key.isEmpty && matchKeys.contains(key)
            }
    }

    private func sourceLooselyMatches(_ source: SearchItem, matchKeys: Set<String>) -> Bool {
        [source.name, source.nameCn, source.displayName]
            .map(normalizedStrictSourceName)
            .contains { sourceKey in
                guard sourceKey.count >= 4 else { return false }
                return matchKeys.contains { matchKey in
                    guard matchKey.count >= 4 else { return false }
                    return sourceKey.contains(matchKey) || matchKey.contains(sourceKey)
                }
            }
    }

    private func normalizedStrictSourceName(_ value: String) -> String {
        value
            .precomposedStringWithCompatibilityMapping
            .lowercased()
            .replacingOccurrences(of: "第2季", with: "第二季")
            .replacingOccurrences(of: "第3季", with: "第三季")
            .replacingOccurrences(of: "第4季", with: "第四季")
            .replacingOccurrences(of: "第5季", with: "第五季")
            .filter { $0.isLetter || $0.isNumber || $0.isChinese }
            .map(String.init)
            .joined()
    }
}

private extension Character {
    var isChinese: Bool {
        unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        }
    }
}

#Preview {
    NavigationStack {
        BangumiDetailView(bangumi: Bangumi.sample, searchItem: nil)
    }
    .preferredColorScheme(.dark)
}
