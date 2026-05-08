//
//  CollectedBangumiDetailView.swift
//  KazumiTV
//
//  Collected Bangumi Detail Screen with episodes and progress
//

import SwiftUI

struct CollectedBangumiDetailView: View {
    let collected: CollectedBangumi
    @StateObject private var viewModel = CollectedBangumiDetailViewModel()
    @ObservedObject private var router = Router.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header with cover and info
                headerSection

                // Progress section
                progressSection

                // Episodes
                episodesSection
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 32)
        }
        .background(Color.kzBackground)
        .navigationTitle(collected.displayName)
        .task {
            await viewModel.loadEpisodes(bangumiId: collected.bangumiId)
        }
    }

    private var bangumiForPlayer: Bangumi {
        viewModel.bangumi ?? Bangumi(
            id: collected.bangumiId,
            type: 2,
            name: collected.name,
            nameCn: collected.nameCn,
            summary: "",
            airDate: "",
            airWeekday: 0,
            rank: 0,
            images: ["large": collected.imageURL],
            tags: [],
            alias: [],
            ratingScore: 0,
            votes: 0,
            votesCount: [],
            info: ""
        )
    }

    // MARK: - Header Section
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 24) {
            // Cover image
            ZStack {
                Rectangle()
                    .fill(Color.kzCardBackground)

                if let url = URL(string: collected.imageURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        default:
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundColor(.kzTextSecondary)
                        }
                    }
                } else {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.kzTextSecondary)
                }
            }
            .aspectRatio(0.65, contentMode: .fit)
            .frame(width: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Info
            VStack(alignment: .leading, spacing: 12) {
                Text(collected.displayName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.kzText)

                // Status badge
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.kzPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.kzPrimary.opacity(0.2))
                    .clipShape(Capsule())

                // Episode count
                Text("\(collected.airedEps)/\(collected.eps)话")
                    .font(.subheadline)
                    .foregroundColor(.kzTextSecondary)

                Spacer()

                // Continue watching button
                if let lastEp = collected.lastWatchedEpisode, lastEp < collected.eps {
                    Button {
                        playEpisode(number: lastEp + 1)
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("继续观看")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.kzPrimary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(TVPillButtonStyle())
                } else if collected.eps > 0 {
                    Button {
                        playEpisode(number: 1)
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("开始观看")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.kzPrimary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(TVPillButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusText: String {
        switch collected.type {
        case 1: return "在看"
        case 2: return "想看"
        case 3: return "搁置"
        case 4: return "看过"
        case 5: return "抛弃"
        default: return "未知"
        }
    }

    private func playEpisode(number: Int) {
        let episode = Episode(
            id: number,
            bangumiId: collected.bangumiId,
            episodeNumber: number,
            name: "第\(number)话",
            nameCn: "",
            airDate: "",
            duration: "",
            description: "",
            type: .normal,
            pageURL: nil,
            pluginName: nil
        )
        router.navigate(to: .player(bangumi: bangumiForPlayer, episode: episode))
    }

    // MARK: - Progress Section
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("观看进度")
                .font(.headline)
                .foregroundColor(.kzText)

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.kzSurface)
                        .frame(height: 8)
                        .clipShape(Capsule())

                    Rectangle()
                        .fill(Color.kzPrimary)
                        .frame(width: geometry.size.width * collected.progressPercentage, height: 8)
                        .clipShape(Capsule())
                }
            }
            .frame(height: 8)

            Text("\(collected.watchProgress.count) / \(collected.eps) 话")
                .font(.caption)
                .foregroundColor(.kzTextSecondary)
        }
    }

    // MARK: - Episodes Section
    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("章节")
                    .font(.headline)
                    .foregroundColor(.kzText)

                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                        .tint(.kzPrimary)
                        .scaleEffect(0.8)
                }
            }

            if viewModel.episodes.isEmpty && !viewModel.isLoading {
                Text("暂无章节信息")
                    .font(.subheadline)
                    .foregroundColor(.kzTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(viewModel.episodes) { episode in
                        CollectedEpisodeCard(
                            episode: episode,
                            progress: collected.watchProgress[episode.episodeNumber]
                        ) {
                            router.navigate(to: .player(bangumi: bangumiForPlayer, episode: episode))
                        }
                        .buttonStyle(TVCardButtonStyle())
                    }
                }
            }
        }
    }
}

// MARK: - Collected Episode Card
struct CollectedEpisodeCard: View {
    let episode: Episode
    let progress: Double?
    let onTap: () -> Void

    private var isWatched: Bool {
        progress != nil && progress! >= 0.9
    }

    private var isInProgress: Bool {
        progress != nil && progress! > 0 && progress! < 0.9
    }

    var body: some View {
        Button {
            onTap()
        } label: {
            ZStack {
                VStack(spacing: 4) {
                    Text(episode.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(isWatched ? .kzTextSecondary : .kzText)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    if !episode.airDate.isEmpty {
                        Text(episode.airDate)
                            .font(.caption2)
                            .foregroundColor(.kzTextSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
                .background(Color.kzSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Progress indicator
                if let prog = progress, prog > 0 && prog < 1 {
                    VStack {
                        Spacer()
                        GeometryReader { geo in
                            Rectangle()
                                .fill(Color.kzPrimary)
                                .frame(width: geo.size.width * prog, height: 3)
                        }
                        .frame(height: 3)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Watched checkmark
                if isWatched {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.kzPrimary)
                        }
                        Spacer()
                    }
                    .padding(6)
                }
            }
        }
        .buttonStyle(TVCardButtonStyle())
    }
}

// MARK: - ViewModel
@MainActor
class CollectedBangumiDetailViewModel: ObservableObject {
    @Published var episodes: [Episode] = []
    @Published var bangumi: Bangumi?
    @Published var isLoading = false
    @Published var error: Error?

    private let bangumiAPI = BangumiAPI.shared

    func loadEpisodes(bangumiId: Int) async {
        isLoading = true
        do {
            episodes = try await bangumiAPI.getEpisodes(subjectId: bangumiId)
        } catch {
            self.error = error
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        CollectedBangumiDetailView(collected: CollectedBangumi.sample)
    }
    .preferredColorScheme(.dark)
}
