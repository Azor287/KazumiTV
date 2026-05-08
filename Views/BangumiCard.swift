//
//  BangumiCard.swift
//  KazumiTV
//
//  Bangumi Card Component - Vertical layout with cover + title
//

import SwiftUI

struct BangumiCard: View {
    let bangumi: Bangumi

    // 0.65 aspect ratio (matching original Flutter app)
    private let cardAspectRatio: CGFloat = 0.65

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover image
            ZStack {
                Rectangle()
                    .fill(Color.kzCardBackground)

                if let imageURL = bangumi.largeImage {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            loadingPlaceholder
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            errorPlaceholder
                        @unknown default:
                            errorPlaceholder
                        }
                    }
                } else {
                    // Placeholder when no thumbnail
                    VStack {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.kzTextSecondary.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .aspectRatio(cardAspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Title
            Text(bangumi.displayName)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.kzText)
                .lineLimit(3)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
        }
        .background(Color.kzSurfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var loadingPlaceholder: some View {
        Rectangle()
            .fill(Color.kzCardBackground)
            .overlay {
                ProgressView()
                    .tint(.kzTextSecondary)
            }
    }

    private var errorPlaceholder: some View {
        Rectangle()
            .fill(Color.kzCardBackground)
            .overlay {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundColor(.kzTextSecondary)
            }
    }
}

// MARK: - Featured Card (Larger)
struct FeaturedBangumiCard: View {
    let bangumi: Bangumi

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover image - larger for featured
            ZStack {
                Rectangle()
                    .fill(Color.kzCardBackground)

                if let imageURL = bangumi.largeImage {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .tint(.white)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundColor(.kzTextSecondary)
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.kzTextSecondary.opacity(0.5))
                }
            }
            .aspectRatio(16/9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Title
            Text(bangumi.displayName)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.kzText)
                .lineLimit(2)

            // Rating info
            HStack {
                if bangumi.ratingScore > 0 {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                    Text(String(format: "%.1f", bangumi.ratingScore))
                        .font(.caption)
                        .foregroundColor(.kzTextSecondary)
                }

                Spacer()

                Text("\(bangumi.airDate)")
                    .font(.caption)
                    .foregroundColor(.kzTextSecondary)
            }
        }
        .frame(width: 280)
        .padding(8)
        .background(Color.kzSurfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Horizontal Card (For Timeline/Collect)
struct HorizontalBangumiCard: View {
    let bangumi: Bangumi

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            ZStack {
                Rectangle()
                    .fill(Color.kzCardBackground)

                if let imageURL = bangumi.mediumImage {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        default:
                            EmptyView()
                        }
                    }
                } else {
                    Image(systemName: "play.rectangle.fill")
                        .foregroundColor(.kzTextSecondary)
                }
            }
            .frame(width: 120, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(bangumi.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.kzText)
                    .lineLimit(2)

                Text(bangumi.airDate)
                    .font(.caption)
                    .foregroundColor(.kzTextSecondary)
            }

            Spacer()
        }
        .padding(8)
        .background(Color.kzSurfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    VStack {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(Bangumi.samples) { bangumi in
                Button {
                } label: {
                    BangumiCard(bangumi: bangumi)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding()
    }
    .background(Color.kzBackground)
    .preferredColorScheme(.dark)
}
