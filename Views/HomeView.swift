//
//  HomeView.swift
//  KazumiTV
//
//  Home Screen with Featured Content
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @State private var featuredVideos: [Video] = []
    @State private var recentVideos: [Video] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 400)
                } else {
                    // Featured Section
                    FeaturedSection(videos: featuredVideos)

                    // Recent Section
                    RecentSection(videos: recentVideos)
                }
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 32)
        }
        .background(Color.black.opacity(0.95))
        .navigationTitle("KazumiTV")
        .task {
            await loadContent()
        }
    }

    private func loadContent() async {
        isLoading = true
        defer { isLoading = false }

        do {
            featuredVideos = try await appState.videoService.fetchFeaturedVideos()
            recentVideos = try await appState.videoService.fetchRecentVideos()
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Featured Section
struct FeaturedSection: View {
    let videos: [Video]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Featured")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(videos) { video in
                        NavigationLink(destination: VideoDetailView(video: video)) {
                            FeaturedVideoCard(video: video)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }
}

// MARK: - Recent Section
struct RecentSection: View {
    let videos: [Video]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 24) {
                ForEach(videos) { video in
                    NavigationLink(destination: VideoDetailView(video: video)) {
                        VideoCard(video: video)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
}

// MARK: - Featured Video Card
struct FeaturedVideoCard: View {
    let video: Video

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(16/9, contentMode: .fit)

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.white.opacity(0.8))
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(video.title)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(2)

            Text(video.category)
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .frame(width: 400)
    }
}

// MARK: - Video Card
struct VideoCard: View {
    let video: Video

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(16/9, contentMode: .fit)

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.white.opacity(0.8))
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(video.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(2)

            Text(video.category)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .environmentObject(AppState())
    }
}
