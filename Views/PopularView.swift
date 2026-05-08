//
//  PopularView.swift
//  KazumiTV
//
//  Popular Bangumi View - Grid layout with consistent row heights
//

import SwiftUI
import Kingfisher

struct PopularView: View {
    @StateObject private var viewModel = PopularViewModel()
    @ObservedObject private var router = Router.shared
    @Environment(\.resetFocus) private var resetFocus
    @Namespace private var cardFocusScope
    @FocusState private var focusedBangumiID: Int?
    @State private var pendingFocusRestoreBangumiID: Int?
    @State private var lastLoadMoreTriggerID: Int?

    var body: some View {
        GeometryReader { geometry in
            let columnCount = calculateColumnCount(width: geometry.size.width)
            let cardWidth = (geometry.size.width - 16 - CGFloat(columnCount - 1) * 8) / CGFloat(columnCount)

            ScrollView {
                VStack(spacing: 0) {
                    headerView

                    if viewModel.isLoading && viewModel.popularBangumis.isEmpty {
                        loadingView
                    } else if viewModel.popularBangumis.isEmpty {
                        emptyView
                    } else {
                        // Row-based grid
                        LazyVStack(spacing: 12) {
                            ForEach(Array(viewModel.popularBangumis.chunked(into: columnCount).enumerated()), id: \.offset) { rowIndex, rowItems in
                                HStack(spacing: 8) {
                                    ForEach(rowItems) { bangumi in
                                        Button {
                                            pendingFocusRestoreBangumiID = bangumi.id
                                            focusedBangumiID = bangumi.id
                                            router.navigate(to: .bangumiDetail(bangumi, nil))
                                        } label: {
                                            GridBangumiCard(bangumi: bangumi, cardWidth: cardWidth)
                                        }
                                        .buttonStyle(TVCardButtonStyle())
                                        .focused($focusedBangumiID, equals: bangumi.id)
                                        .zIndex(focusedBangumiID == bangumi.id ? 20 : 0)
                                    }
                                    // Fill empty slots
                                    ForEach(0..<(columnCount - rowItems.count), id: \.self) { _ in
                                        Color.clear
                                            .frame(width: cardWidth)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .zIndex(rowItems.contains { $0.id == focusedBangumiID } ? 10 : 0)
                                .onAppear {
                                    if let lastID = rowItems.last?.id,
                                       lastID == viewModel.popularBangumis.last?.id,
                                       lastLoadMoreTriggerID != lastID {
                                        lastLoadMoreTriggerID = lastID
                                        Task {
                                            await viewModel.loadMore()
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 16)
                        .focusScope(cardFocusScope)
                        .focusSection()

                        if viewModel.isLoadingMore {
                            ProgressView()
                                .tint(.white)
                                .padding()
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.kzBackground)
        .task {
            await viewModel.loadDataIfNeeded()
            scheduleCardFocusRestore()
        }
        .onAppear {
            scheduleCardFocusRestore()
        }
    }

    private var headerView: some View {
        HStack {
            Text("热门番剧")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.kzText)

            Spacer()

            Button {
                Task {
                    await viewModel.refresh()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.title3)
                    .foregroundColor(.kzTextSecondary)
            }
            .buttonStyle(TVIconButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.kzBackground)
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .tint(.kzPrimary)
                .scaleEffect(1.5)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("什么都没有找到 (´;ω;`)")
                .font(.headline)
                .foregroundColor(.kzTextSecondary)
            Button("点击重试") {
                Task {
                    await viewModel.refresh()
                }
            }
            .foregroundColor(.kzPrimary)
            .buttonStyle(TVPillButtonStyle())
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }

    private func scheduleCardFocusRestore() {
        guard let targetID = pendingFocusRestoreBangumiID ?? focusedBangumiID,
              viewModel.popularBangumis.contains(where: { $0.id == targetID }) else {
            return
        }

        DispatchQueue.main.async {
            focusedBangumiID = targetID
            resetFocus(in: cardFocusScope)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            focusedBangumiID = targetID
            resetFocus(in: cardFocusScope)
        }
    }

    private func calculateColumnCount(width: CGFloat) -> Int {
        if width > 1200 { return 6 }
        if width > 900 { return 5 }
        if width > 600 { return 4 }
        return 3
    }
}

// MARK: - Grid BangumiCard with fixed title height
struct GridBangumiCard: View {
    let bangumi: Bangumi
    var cardWidth: CGFloat
    @Environment(\.isFocused) private var isFocused

    private let cardAspectRatio: CGFloat = 0.65

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover image
            ZStack {
                Rectangle()
                    .fill(Color.kzCardBackground)

                if let imageURL = bangumi.largeImage {
                    KFImage(imageURL)
                        .placeholder {
                            loadingPlaceholder
                        }
                        .retry(maxCount: 2, interval: .seconds(1))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    errorPlaceholder
                }
            }
            .aspectRatio(cardAspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Title - fixed height for 2 lines
            Text(bangumi.displayName)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.kzText)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 54)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        .frame(width: cardWidth)
        .background(Color.kzSurfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isFocused ? Color.kzPrimary.opacity(0.88) : Color.clear,
                    lineWidth: 2.5
                )
        }
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

// MARK: - Array Extension
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

#Preview {
    PopularView()
}
