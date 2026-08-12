//
//  CollectView.swift
//  KazumiTV
//
//  Collection View - User's favorited anime
//

import SwiftUI
import UIKit

struct CollectView: View {
    @StateObject private var viewModel = CollectViewModel()
    @ObservedObject private var router = Router.shared
    @Environment(\.resetFocus) private var resetFocus
    @Namespace private var cardFocusScope
    @State private var selectedFilter: CollectViewModel.CollectionFilter = .all
    @FocusState private var focusedBangumiID: Int?
    @State private var pendingFocusRestoreBangumiID: Int?
    private let cardFocusOutset: CGFloat = 18

    var body: some View {
        GeometryReader { geometry in
            let columnCount = calculateColumnCount(width: geometry.size.width)
            let cardWidth = (geometry.size.width - 48 - CGFloat(columnCount - 1) * 8) / CGFloat(columnCount)

            VStack(spacing: 0) {
                // Filter tabs
                filterTabs

                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                        .tint(.kzPrimary)
                    Spacer()
                } else if viewModel.filteredCollections.isEmpty {
                    emptyView
                } else {
                    gridView(columnCount: columnCount, cardWidth: cardWidth)
                }
            }
        }
        .background(Color.kzBackground)
        .onAppear {
            Task {
                await viewModel.loadDataIfNeeded()
                scheduleCardFocusRestore()
            }
        }
    }

    private var filterTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CollectViewModel.CollectionFilter.allCases, id: \.self) { filter in
                    Button {
                        selectedFilter = filter
                        viewModel.selectedFilter = filter
                        focusedBangumiID = nil
                        pendingFocusRestoreBangumiID = nil
                    } label: {
                        Text(filter.rawValue)
                            .font(.subheadline)
                            .foregroundColor(selectedFilter == filter ? .kzPrimary : .kzTextSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedFilter == filter ? Color.kzPrimary.opacity(0.2) : Color.clear)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(TVPillButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "heart")
                .font(.system(size: 60))
                .foregroundColor(.kzTextSecondary.opacity(0.5))
            Text("还没有收藏任何番剧")
                .font(.headline)
                .foregroundColor(.kzTextSecondary)
            Text("去推荐页面看看吧")
                .font(.subheadline)
                .foregroundColor(.kzTextSecondary.opacity(0.7))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func gridView(columnCount: Int, cardWidth: CGFloat) -> some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(Array(viewModel.filteredCollections.chunked(into: columnCount).enumerated()), id: \.offset) { _, rowItems in
                    let titleHeight = rowTitleHeight(for: rowItems, cardWidth: cardWidth)
                    let cardHeight = cardWidth / 0.65 + titleHeight + 30
                    let rowHeight = cardHeight + cardFocusOutset

                    HStack(spacing: 8) {
                        ForEach(rowItems) { collected in
                            Button {
                                pendingFocusRestoreBangumiID = collected.bangumiId
                                focusedBangumiID = collected.bangumiId
                                router.navigate(to: .bangumiDetail(bangumi(from: collected), nil))
                            } label: {
                                CollectedBangumiCard(
                                    collected: collected,
                                    cardWidth: cardWidth,
                                    titleHeight: titleHeight
                                )
                            }
                            .buttonStyle(TVCardButtonStyle())
                            .focused($focusedBangumiID, equals: collected.bangumiId)
                            .zIndex(focusedBangumiID == collected.bangumiId ? 20 : 0)
                        }

                        ForEach(0..<(columnCount - rowItems.count), id: \.self) { _ in
                            Color.clear
                                .frame(width: cardWidth, height: cardHeight)
                        }
                    }
                    .padding(.bottom, cardFocusOutset)
                    .frame(height: rowHeight, alignment: .top)
                    .zIndex(rowItems.contains { $0.bangumiId == focusedBangumiID } ? 10 : 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .focusScope(cardFocusScope)
        .focusSection()
    }

    private func calculateColumnCount(width: CGFloat) -> Int {
        if width > 840 { return 5 }
        if width > 600 { return 4 }
        return 3
    }

    private func rowTitleHeight(for rowItems: [CollectedBangumi], cardWidth: CGFloat) -> CGFloat {
        let textWidth = max(cardWidth - 16, 1)
        let font = UIFont.preferredFont(forTextStyle: .subheadline)
        let boldFont = UIFont.systemFont(ofSize: font.pointSize, weight: .bold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: boldFont,
            .paragraphStyle: paragraphStyle
        ]
        let contentHeight = rowItems
            .map { item in
                let boundingSize = CGSize(width: textWidth, height: .greatestFiniteMagnitude)
                let rect = NSString(string: item.displayName).boundingRect(
                    with: boundingSize,
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                )
                return ceil(rect.height)
            }
            .max() ?? 0

        return max(54, contentHeight + 14)
    }

    private func bangumi(from collected: CollectedBangumi) -> Bangumi {
        Bangumi(
            id: collected.bangumiId,
            type: 2,
            name: collected.name,
            nameCn: collected.nameCn,
            summary: "",
            airDate: "",
            airWeekday: 0,
            rank: 0,
            images: ["large": collected.imageURL, "common": collected.imageURL],
            tags: [],
            alias: [],
            ratingScore: 0,
            votes: 0,
            votesCount: [],
            info: ""
        )
    }

    private func scheduleCardFocusRestore() {
        guard let targetID = pendingFocusRestoreBangumiID ?? focusedBangumiID,
              viewModel.filteredCollections.contains(where: { $0.bangumiId == targetID }) else {
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
}

// MARK: - CollectedBangumiCard
struct CollectedBangumiCard: View {
    let collected: CollectedBangumi
    var cardWidth: CGFloat = 260
    var titleHeight: CGFloat = 54
    @Environment(\.isFocused) private var isFocused

    private var posterHeight: CGFloat {
        cardWidth / 0.65
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AsyncImage(url: URL(string: collected.imageURL)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.3)
            }
            .frame(width: cardWidth, height: posterHeight)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(collected.displayName)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.kzText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: titleHeight, alignment: .topLeading)

            Text(collected.collectionTypeText)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.kzTextSecondary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: cardWidth, height: posterHeight + titleHeight + 30, alignment: .top)
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
}

#Preview {
    CollectView()
}
