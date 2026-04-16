//
//  VideoDetailView.swift
//  KazumiTV
//
//  Video Detail Screen with Player
//

import SwiftUI
import AVKit

struct VideoDetailView: View {
    let video: Video
    @EnvironmentObject var appState: AppState
    @State private var player: AVPlayer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Video Player
                VideoPlayerView(player: player)
                    .aspectRatio(16/9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                // Video Info
                VStack(alignment: .leading, spacing: 16) {
                    Text(video.title)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    HStack {
                        Text(video.category)
                            .font(.subheadline)
                            .foregroundColor(.gray)

                        Spacer()

                        Text(video.duration)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }

                    Text(video.description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(nil)
                }
                .padding(.horizontal, 16)
            }
            .padding(32)
        }
        .background(Color.black)
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    private func setupPlayer() {
        // Placeholder player setup
        // In production, use video.streamURL
        player = AVPlayer(url: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!)
    }
}

// MARK: - Video Player View
struct VideoPlayerView: View {
    let player: AVPlayer?

    var body: some View {
        if let player = player {
            VideoPlayer(player: player)
                .disabled(true)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .aspectRatio(16/9, contentMode: .fit)
                .overlay(
                    ProgressView()
                        .tint(.white)
                )
        }
    }
}

#Preview {
    NavigationStack {
        VideoDetailView(video: Video(
            id: "1",
            title: "Big Buck Bunny",
            description: "A large rabbit meets three bullying rodents.",
            category: "Animation",
            duration: "9:56",
            thumbnailURL: nil,
            streamURL: nil
        ))
        .environmentObject(AppState())
    }
}
