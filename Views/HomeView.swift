//
//  HomeView.swift
//  KazumiTV
//
//  Home Screen with Featured Content
//

import SwiftUI
import UIKit
import Kingfisher

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @ObservedObject private var router = Router.shared
    @State private var showingCategoryPicker = false
    @FocusState private var focusedBangumiID: Int?
    @FocusState private var focusedCategoryID: String?
    @FocusState private var retryPromptFocused: Bool
    private let cardFocusOutset: CGFloat = 18

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                let columnCount = calculateColumnCount(width: geometry.size.width)
                let cardWidth = (geometry.size.width - 48 - CGFloat(columnCount - 1) * 8) / CGFloat(columnCount)

                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            Color.clear
                                .frame(height: 0)
                                .id(HomeScrollTarget.top)

                            headerView

                            if viewModel.isLoading || (viewModel.isLoadingTrends && viewModel.trends.isEmpty) {
                                ProgressView()
                                    .tint(.kzPrimary)
                                    .frame(maxWidth: .infinity, minHeight: 420)
                            } else if viewModel.trends.isEmpty {
                                emptyView
                            } else {
                                gridView(columnCount: columnCount, cardWidth: cardWidth)
                                    .opacity(viewModel.isLoadingTrends ? 0.38 : 1)
                                    .overlay {
                                        if viewModel.isLoadingTrends {
                                            loadingIndicator
                                        }
                                    }
                                    .disabled(viewModel.isLoadingTrends)

                                if viewModel.isLoadingMore && !viewModel.isLoadingTrends {
                                    ProgressView()
                                        .tint(.kzPrimary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 24)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                    .disabled(showingCategoryPicker)
                    .background {
                        PlayPauseLongPressReader {
                            guard !showingCategoryPicker else { return }
                            scrollToTopAndFocusFirstCard(with: scrollProxy)
                        }
                    }
                    .overlay {
                        if showingCategoryPicker {
                            categoryPickerOverlay(scrollProxy: scrollProxy)
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        }
                    }
                }
            }
        }
        .background(Color.kzBackground)
        .animation(.easeOut(duration: 0.16), value: showingCategoryPicker)
        .onPlayPauseCommand {
            retryHomeCardsIfNeeded()
        }
        .task {
            await viewModel.loadData()
        }
    }

    private var headerView: some View {
        HStack(alignment: .center) {
            Button {
                presentCategoryPicker()
            } label: {
                HStack(spacing: 14) {
                    Text(viewModel.selectedCategory.title)
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.title3.weight(.bold))
                        .frame(width: 44, height: 44)
                        .background(Color.kzText.opacity(0.08))
                        .clipShape(Circle())
                }
                .foregroundColor(.kzText)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(HomeCategoryMenuButtonStyle())

            Spacer()
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var loadingIndicator: some View {
        ProgressView()
            .tint(.kzPrimary)
            .scaleEffect(1.35)
            .frame(maxWidth: .infinity, minHeight: 420)
            .background(Color.kzBackground.opacity(0.28))
    }

    private func categoryPickerOverlay(scrollProxy: ScrollViewProxy) -> some View {
        GeometryReader { geometry in
            let panelWidth = min(max(geometry.size.width - 96, 780), 1080)

            ZStack {
                Color.black.opacity(0.52)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 28) {
                    Text("番组标签")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.kzText)

                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: 224), spacing: 18)
                        ],
                        alignment: .leading,
                        spacing: 18
                    ) {
                        ForEach(HomeBangumiCategory.all) { category in
                            categoryButton(category, scrollProxy: scrollProxy)
                        }
                    }
                }
                .padding(40)
                .frame(width: panelWidth, alignment: .leading)
                .background(Color.kzBackground)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Color.black.opacity(0.42), radius: 24, x: 0, y: 16)
            }
        }
        .onAppear {
            focusedCategoryID = viewModel.selectedCategory.id
        }
        .onExitCommand {
            dismissCategoryPicker()
        }
    }

    private func categoryButton(
        _ category: HomeBangumiCategory,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        let isSelected = category == viewModel.selectedCategory

        return Button {
            selectCategory(category, scrollProxy: scrollProxy)
        } label: {
            HStack(spacing: 10) {
                Text(category.title)
                    .font(.title3)
                    .fontWeight(isSelected ? .bold : .semibold)
                    .foregroundStyle(isSelected ? Color.kzOnPrimaryContainer : Color.kzText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .layoutPriority(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .frame(height: 64)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.kzPrimaryContainer.opacity(0.95) : Color.kzSurfaceContainerLow)
            )
        }
        .buttonStyle(TVPillButtonStyle())
        .focused($focusedCategoryID, equals: category.id)
    }

    private var emptyView: some View {
        VStack(spacing: 18) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48, weight: .semibold))
                .foregroundColor(.kzPrimary)

            Text(viewModel.error == nil ? "暂时没有加载到番组" : "加载失败")
                .font(.title3.weight(.semibold))
                .foregroundColor(.kzText)

            if let error = viewModel.error {
                Text(userFacingErrorMessage(error))
                    .font(.subheadline)
                    .foregroundColor(.kzTextSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }

            Label("按播放键重试", systemImage: "play.fill")
                .font(.headline.weight(.semibold))
                .foregroundColor(.kzText)
        }
        .frame(maxWidth: .infinity, minHeight: 420)
        .contentShape(Rectangle())
        .focusable()
        .focused($retryPromptFocused)
        .onAppear {
            retryPromptFocused = true
        }
    }

    private func gridView(columnCount: Int, cardWidth: CGFloat) -> some View {
        LazyVStack(spacing: 8) {
            ForEach(Array(viewModel.trends.chunked(into: columnCount).enumerated()), id: \.offset) { _, rowItems in
                let titleHeight = rowTitleHeight(for: rowItems, cardWidth: cardWidth)
                let cardHeight = cardWidth / 0.65 + titleHeight
                let rowHeight = cardHeight + cardFocusOutset

                HStack(spacing: 8) {
                    ForEach(rowItems) { bangumi in
                        Button {
                            router.navigate(to: .bangumiDetail(bangumi, nil))
                        } label: {
                            KazumiBangumiCard(
                                bangumi: bangumi,
                                width: cardWidth,
                                titleHeight: titleHeight
                            )
                        }
                        .buttonStyle(TVCardButtonStyle())
                        .focused($focusedBangumiID, equals: bangumi.id)
                        .zIndex(focusedBangumiID == bangumi.id ? 20 : 0)
                    }

                    ForEach(0..<(columnCount - rowItems.count), id: \.self) { _ in
                        Color.clear
                            .frame(width: cardWidth, height: cardHeight)
                    }
                }
                .padding(.bottom, cardFocusOutset)
                .frame(height: rowHeight, alignment: .top)
                .zIndex(rowItems.contains { $0.id == focusedBangumiID } ? 10 : 0)
                .onAppear {
                    if rowItems.last?.id == viewModel.trends.last?.id {
                        Task {
                            await viewModel.loadMoreTrends()
                        }
                    }
                }
            }
        }
    }

    private func calculateColumnCount(width: CGFloat) -> Int {
        if width > 840 { return 5 }
        if width > 600 { return 4 }
        return 3
    }

    private func rowTitleHeight(for rowItems: [Bangumi], cardWidth: CGFloat) -> CGFloat {
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

    private func scrollToTopAndFocusFirstCard(with scrollProxy: ScrollViewProxy) {
        guard let firstBangumiID = viewModel.trends.first?.id else { return }

        withAnimation(.easeInOut(duration: 0.24)) {
            scrollProxy.scrollTo(HomeScrollTarget.top, anchor: .top)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            focusedBangumiID = firstBangumiID
        }
    }

    private func presentCategoryPicker() {
        focusedBangumiID = nil
        showingCategoryPicker = true
    }

    private func dismissCategoryPicker() {
        showingCategoryPicker = false
        focusedCategoryID = nil
    }

    private func selectCategory(
        _ category: HomeBangumiCategory,
        scrollProxy: ScrollViewProxy
    ) {
        dismissCategoryPicker()

        Task {
            withAnimation(.easeInOut(duration: 0.2)) {
                scrollProxy.scrollTo(HomeScrollTarget.top, anchor: .top)
            }

            await viewModel.selectCategory(category)

            DispatchQueue.main.async {
                focusedBangumiID = viewModel.trends.first?.id
            }
        }
    }

    private func retryHomeCardsIfNeeded() {
        guard !showingCategoryPicker,
              viewModel.trends.isEmpty,
              !viewModel.isLoading,
              !viewModel.isLoadingTrends else {
            return
        }

        Task {
            retryPromptFocused = true
            await viewModel.refresh()
            focusedBangumiID = viewModel.trends.first?.id
        }
    }

    private func userFacingErrorMessage(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorSecureConnectionFailed,
                 NSURLErrorServerCertificateHasBadDate,
                 NSURLErrorServerCertificateUntrusted,
                 NSURLErrorServerCertificateHasUnknownRoot,
                 NSURLErrorServerCertificateNotYetValid,
                 NSURLErrorClientCertificateRejected,
                 NSURLErrorClientCertificateRequired:
                return "安全连接失败"
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorTimedOut:
                return "网络连接异常"
            default:
                return "番组列表加载失败"
            }
        }

        return error.localizedDescription
    }
}

private enum HomeScrollTarget: Hashable {
    case top
}

private struct HomeCategoryMenuButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isFocused ? Color.kzPrimaryContainer.opacity(0.42) : Color.clear)
            )
            .shadow(
                color: isFocused ? Color.kzPrimary.opacity(0.16) : Color.clear,
                radius: isFocused ? 14 : 0,
                x: 0,
                y: isFocused ? 6 : 0
            )
            .scaleEffect(isFocused ? 1.025 : 1.0)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: 0.16), value: isFocused)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct PlayPauseLongPressReader: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear

        let recognizer = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        recognizer.minimumPressDuration = 0.55
        recognizer.allowedPressTypes = [NSNumber(value: UIPress.PressType.playPause.rawValue)]
        view.addGestureRecognizer(recognizer)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began else { return }
            action()
        }
    }
}

struct KazumiBangumiCard: View {
    let bangumi: Bangumi
    let width: CGFloat
    let titleHeight: CGFloat
    @Environment(\.isFocused) private var isFocused

    private var imageHeight: CGFloat {
        width / 0.65
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Rectangle()
                    .fill(Color.kzCardBackground)

                if let imageURL = bangumi.largeImage {
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
                        .font(.title2)
                        .foregroundColor(.kzTextSecondary)
                }
            }
            .frame(width: width, height: imageHeight)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(bangumi.displayName)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.kzText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: titleHeight, alignment: .topLeading)
        }
        .frame(width: width, height: imageHeight + titleHeight, alignment: .top)
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


// MARK: - Row Data
private struct RowData: Identifiable {
    let id: Int
    let items: [Bangumi]
}

// MARK: - Fixed Row Grid Layout
struct FixedRowGrid: View {
    let items: [Bangumi]
    let columns: Int
    let spacing: CGFloat
    @ObservedObject private var router = Router.shared

    private let cardRatio: CGFloat = 0.65 // width / height

    private var rows: [RowData] {
        let rowCount = (items.count + columns - 1) / columns
        return (0..<rowCount).map { rowIndex in
            let startIndex = rowIndex * columns
            let endIndex = min(startIndex + columns, items.count)
            let rowItems = Array(items[startIndex..<endIndex])
            return RowData(id: rowIndex, items: rowItems)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let cardWidth = (geometry.size.width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
            let imageHeight = cardWidth / cardRatio
            let titleHeight: CGFloat = 46
            let rowHeight = imageHeight + titleHeight + 8

            LazyVStack(spacing: spacing) {
                ForEach(rows) { row in
                    HStack(spacing: spacing) {
                        ForEach(row.items) { bangumi in
                            Button {
                                router.navigate(to: .bangumiDetail(bangumi, nil))
                            } label: {
                                VerticalCard(
                                    bangumi: bangumi,
                                    width: cardWidth,
                                    imageHeight: imageHeight,
                                    titleHeight: titleHeight
                                )
                            }
                            .buttonStyle(TVCardButtonStyle())
                        }
                        // Fill empty slots
                        ForEach(0..<(columns - row.items.count), id: \.self) { _ in
                            Color.clear
                                .frame(width: cardWidth, height: rowHeight)
                        }
                    }
                    .frame(height: rowHeight)
                }
            }
        }
        .frame(height: calculatedTotalHeight)
    }

    private var calculatedTotalHeight: CGFloat {
        let rowCount = (items.count + columns - 1) / columns
        let availableWidth = max(UIScreen.main.bounds.width - 96, 700)
        let cardWidth = (availableWidth - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        let imageHeight = cardWidth / cardRatio
        let rowHeight = imageHeight + 54
        return CGFloat(rowCount) * rowHeight + CGFloat(max(rowCount - 1, 0)) * spacing
    }
}

// MARK: - Vertical Card (Portrait style)
struct VerticalCard: View {
    let bangumi: Bangumi
    let width: CGFloat
    let imageHeight: CGFloat
    let titleHeight: CGFloat
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover image - portrait ratio
            AsyncImage(url: bangumi.largeImage) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                default:
                    Rectangle()
                        .fill(Color.kzCardBackground)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundColor(.kzTextSecondary)
                        }
                }
            }
            .frame(width: width, height: imageHeight)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Title
            Text(bangumi.displayName)
                .font(.caption)
                .foregroundColor(.kzText)
                .lineLimit(2)
                .frame(width: width, height: titleHeight, alignment: .topLeading)
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
        }
        .frame(width: width)
        .background(Color.kzSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isFocused ? Color.kzPrimary.opacity(0.88) : Color.clear,
                    lineWidth: 2.5
                )
        }
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .preferredColorScheme(.dark)
}
