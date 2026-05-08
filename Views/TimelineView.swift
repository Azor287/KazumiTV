//
//  TimelineView.swift
//  KazumiTV
//
//  Timeline View - Weekly anime schedule
//

import SwiftUI
import Kingfisher

struct TimelineView: View {
    @StateObject private var viewModel = TimelineViewModel()
    @State private var showingOptionsPanel = false
    @ObservedObject private var router = Router.shared
    @Environment(\.resetFocus) private var resetFocus
    @Namespace private var optionsFocusScope
    @Namespace private var cardFocusScope
    @FocusState private var focusedWeekday: Int?
    @FocusState private var focusedBangumiID: Int?
    @FocusState private var focusedOption: TimelineOptionFocus?
    @State private var pendingFocusRestoreBangumiID: Int?

    private let gridSpacing: CGFloat = 8
    private let gridHorizontalPadding: CGFloat = 8
    private let cardFocusOutset: CGFloat = 18
    private let timelineCardHeight: CGFloat = 160

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    weekdayTabs

                    Divider()
                        .overlay(Color.kzTextSecondary.opacity(0.22))

                    content(width: geometry.size.width)
                }
                .disabled(showingOptionsPanel)

                floatingOptionsButton
                    .padding(.trailing, 24)
                    .padding(.bottom, 28)
                    .disabled(showingOptionsPanel)

                if showingOptionsPanel {
                    optionsPanel
                        .zIndex(10)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
        }
        .background(Color.kzBackground)
        .animation(.easeOut(duration: 0.16), value: showingOptionsPanel)
        .task {
            await viewModel.loadDataIfNeeded()
            scheduleCardFocusRestore()
        }
        .onAppear {
            scheduleCardFocusRestore()
        }
        .onChange(of: viewModel.selectedWeekday) { _, _ in
            focusedBangumiID = nil
            pendingFocusRestoreBangumiID = nil
        }
        .onChange(of: focusedOption) { _, newValue in
            guard showingOptionsPanel, newValue == nil else { return }
            scheduleOptionsPanelFocus()
        }
        .onDisappear {
            if showingOptionsPanel {
                router.setMainChromeHidden(nil)
            }
        }
    }

    private var weekdayTabs: some View {
        HStack(spacing: 0) {
            ForEach(0..<viewModel.weekdayNames.count, id: \.self) { index in
                let item = viewModel.weekdayNames[index]
                weekdayButton(day: item.0, title: item.1)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 68)
        .background(Color.kzBackground)
        .focusSection()
    }

    private func weekdayButton(day: Int, title: String) -> some View {
        let isSelected = viewModel.selectedWeekday == day

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                viewModel.selectWeekday(day)
            }
        } label: {
            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .fontWeight(isSelected ? .bold : .semibold)
                    .foregroundStyle(isSelected ? Color.kzPrimary : Color.kzTextSecondary)
                    .frame(maxWidth: .infinity)

                Capsule()
                    .fill(isSelected ? Color.kzPrimary : Color.clear)
                    .frame(width: 24, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(TimelineWeekdayButtonStyle())
        .focused($focusedWeekday, equals: day)
    }

    @ViewBuilder
    private func content(width: CGFloat) -> some View {
        if viewModel.isLoading && viewModel.calendar.allSatisfy(\.isEmpty) {
            loadingView
        } else if viewModel.selectedDayBangumis.isEmpty {
            emptyView
        } else {
            timelineGrid(items: viewModel.selectedDayBangumis, width: width)
        }
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .tint(.kzPrimary)
                .scaleEffect(1.4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 18) {
            Spacer()

            Text(viewModel.error == nil ? "当天没有待播番剧" : "什么都没有找到 (´;ω;`)")
                .font(.title3.weight(.semibold))
                .foregroundColor(.kzTextSecondary)

            if viewModel.error != nil {
                Button {
                    Task {
                        await viewModel.refresh()
                    }
                } label: {
                    Label("点击重试", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .foregroundColor(.kzOnPrimaryContainer)
                        .frame(width: 168, height: 54)
                }
                .buttonStyle(TVPillButtonStyle())
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func timelineGrid(items: [Bangumi], width: CGFloat) -> some View {
        let columnCount = calculateColumnCount(width: width)
        let horizontalPadding = gridHorizontalPadding + cardFocusOutset
        let contentWidth = max(width - horizontalPadding * 2, 1)
        let cardWidth = (contentWidth - CGFloat(columnCount - 1) * gridSpacing) / CGFloat(columnCount)
        let rowHeight = timelineCardHeight + cardFocusOutset

        return ScrollView {
            LazyVStack(spacing: gridSpacing - 2) {
                ForEach(Array(items.chunked(into: columnCount).enumerated()), id: \.offset) { _, rowItems in
                    HStack(spacing: gridSpacing) {
                        ForEach(rowItems) { bangumi in
                            Button {
                                pendingFocusRestoreBangumiID = bangumi.id
                                focusedBangumiID = bangumi.id
                                router.navigate(to: .bangumiDetail(bangumi, nil))
                            } label: {
                                TimelineBangumiCard(
                                    bangumi: bangumi,
                                    cardWidth: cardWidth,
                                    cardHeight: timelineCardHeight
                                )
                            }
                            .buttonStyle(TVCardButtonStyle())
                            .focused($focusedBangumiID, equals: bangumi.id)
                            .zIndex(focusedBangumiID == bangumi.id ? 20 : 0)
                        }

                        ForEach(0..<(columnCount - rowItems.count), id: \.self) { _ in
                            Color.clear
                                .frame(width: cardWidth, height: timelineCardHeight)
                        }
                    }
                    .padding(.bottom, cardFocusOutset)
                    .frame(height: rowHeight, alignment: .top)
                    .zIndex(rowItems.contains { $0.id == focusedBangumiID } ? 10 : 0)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 116)
        }
        .scrollIndicators(.hidden)
        .focusScope(cardFocusScope)
        .focusSection()
    }

    private var floatingOptionsButton: some View {
        Button {
            presentOptionsPanel()
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.kzOnPrimaryContainer)
                .frame(width: 84, height: 84)
                .background(Color.kzPrimaryContainer)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(TVIconButtonStyle())
        .accessibilityLabel("时间线选项")
    }

    private var optionsPanel: some View {
        GeometryReader { geometry in
            let panelWidth = min(max(geometry.size.width * 0.46, 620), 860)

            ZStack {
                Color.black.opacity(0.52)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismissOptionsPanel()
                    }

                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 16) {
                        Text("时间线选项")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Color.kzText)

                        Spacer()

                        Button {
                            dismissOptionsPanel()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(Color.kzText)
                                .frame(width: 56, height: 56)
                        }
                        .buttonStyle(TVIconButtonStyle())
                        .focused($focusedOption, equals: .close)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("排序方式")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Color.kzTextSecondary)

                        HStack(spacing: 12) {
                            ForEach(TimelineSortType.allCases) { sortType in
                                sortButton(sortType)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("过滤器")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Color.kzTextSecondary)

                        filterButton(
                            title: "不显示已抛弃",
                            icon: "heart.slash",
                            isOn: viewModel.notShowAbandonedBangumis,
                            focus: .abandoned
                        ) {
                            viewModel.setNotShowAbandonedBangumis(!viewModel.notShowAbandonedBangumis)
                        }

                        filterButton(
                            title: "不显示已看过",
                            icon: "checkmark.circle",
                            isOn: viewModel.notShowWatchedBangumis,
                            focus: .watched
                        ) {
                            viewModel.setNotShowWatchedBangumis(!viewModel.notShowWatchedBangumis)
                        }
                    }
                }
                .padding(34)
                .frame(width: panelWidth, alignment: .leading)
                .background(Color.kzBackground)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Color.black.opacity(0.42), radius: 24, x: 0, y: 16)
                .focusScope(optionsFocusScope)
                .focusSection()
            }
        }
        .onAppear {
            scheduleOptionsPanelFocus()
        }
        .onExitCommand {
            dismissOptionsPanel()
        }
    }

    private func sortButton(_ sortType: TimelineSortType) -> some View {
        let isSelected = viewModel.sortType == sortType

        return Button {
            viewModel.changeSortType(sortType)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: sortType.icon)
                    .font(.headline)

                Text(sortType.title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(isSelected ? Color.kzOnPrimaryContainer : Color.kzText)
            .frame(maxWidth: .infinity, minHeight: 60)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.kzPrimaryContainer : Color.kzSurfaceContainerLow)
            )
        }
        .buttonStyle(TVPillButtonStyle())
        .focused($focusedOption, equals: .sort(sortType))
        .prefersDefaultFocus(sortType == viewModel.sortType, in: optionsFocusScope)
    }

    private func filterButton(
        title: String,
        icon: String,
        isOn: Bool,
        focus: TimelineOptionFocus,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.headline)
                    .frame(width: 28)

                Text(title)
                    .font(.headline.weight(.semibold))

                Spacer()

                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
            }
            .foregroundStyle(isOn ? Color.kzOnPrimaryContainer : Color.kzText)
            .padding(.horizontal, 20)
            .frame(height: 62)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isOn ? Color.kzPrimaryContainer.opacity(0.95) : Color.kzSurfaceContainerLow)
            )
        }
        .buttonStyle(TVPillButtonStyle())
        .focused($focusedOption, equals: focus)
    }

    private func presentOptionsPanel() {
        focusedWeekday = nil
        focusedBangumiID = nil
        focusedOption = nil
        router.setMainChromeHidden(true)
        showingOptionsPanel = true
        scheduleOptionsPanelFocus()
    }

    private func scheduleOptionsPanelFocus() {
        let defaultFocus = TimelineOptionFocus.sort(viewModel.sortType)

        DispatchQueue.main.async {
            focusedOption = defaultFocus
            resetFocus(in: optionsFocusScope)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            focusedOption = defaultFocus
            resetFocus(in: optionsFocusScope)
        }
    }

    private func dismissOptionsPanel() {
        showingOptionsPanel = false
        focusedOption = nil
        router.setMainChromeHidden(nil)
    }

    private func scheduleCardFocusRestore() {
        guard !showingOptionsPanel,
              let targetID = pendingFocusRestoreBangumiID ?? focusedBangumiID,
              viewModel.selectedDayBangumis.contains(where: { $0.id == targetID }) else {
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
        if width > 840 { return 3 }
        if width > 600 { return 2 }
        return 1
    }
}

// MARK: - Timeline Bangumi Card
struct TimelineBangumiCard: View {
    let bangumi: Bangumi
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    @Environment(\.isFocused) private var isFocused

    private let horizontalPadding: CGFloat = 12
    private let verticalPadding: CGFloat = 10

    private var contentHeight: CGFloat {
        max(cardHeight - verticalPadding * 2, 1)
    }

    private var imageWidth: CGFloat {
        contentHeight * 0.7
    }

    private var supportingText: String {
        let info = bangumi.info.trimmingCharacters(in: .whitespacesAndNewlines)
        if !info.isEmpty { return info }

        if !bangumi.airDate.isEmpty {
            return bangumi.airDate
        }

        return bangumi.summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            posterImage

            VStack(alignment: .leading, spacing: 0) {
                Text(bangumi.displayName)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.kzText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.88)

                if !supportingText.isEmpty {
                    Text(supportingText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.kzTextSecondary)
                        .lineLimit(3)
                        .padding(.top, 6)
                }

                Spacer(minLength: 8)

                metricsFooter
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(width: cardWidth, height: cardHeight)
        .background(Color.kzSurfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    isFocused ? Color.kzPrimary.opacity(0.88) : Color.clear,
                    lineWidth: 2.5
                )
        }
        .padding(.vertical, 4)
        .frame(width: cardWidth, height: cardHeight + 8)
    }

    private var posterImage: some View {
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
        .frame(width: imageWidth, height: contentHeight)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var metricsFooter: some View {
        HStack(spacing: 9) {
            if bangumi.ratingScore > 0 {
                TimelineMetric(icon: "star.fill", label: String(format: "%.1f", bangumi.ratingScore), color: .kzPrimary)
            }

            if bangumi.rank > 0 {
                TimelineMetric(icon: "chart.bar", label: "#\(bangumi.rank)", color: .kzTextSecondary)
            }

            if bangumi.votes > 0 {
                TimelineMetric(icon: "person.2.fill", label: "\(bangumi.votes)", color: .kzTextSecondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }
}

// MARK: - Timeline Detail Row
struct TimelineBangumiRow: View {
    let bangumi: Bangumi

    var body: some View {
        HStack(spacing: 12) {
            posterImage

            VStack(alignment: .leading, spacing: 6) {
                Text(bangumi.displayName)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.kzText)
                    .lineLimit(2)

                Text(bangumi.info.isEmpty ? bangumi.airDate : bangumi.info)
                    .font(.subheadline)
                    .foregroundColor(.kzTextSecondary)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    if bangumi.ratingScore > 0 {
                        TimelineMetric(icon: "star.fill", label: String(format: "%.1f", bangumi.ratingScore), color: .kzPrimary)
                    }

                    if bangumi.rank > 0 {
                        TimelineMetric(icon: "chart.bar", label: "#\(bangumi.rank)", color: .kzTextSecondary)
                    }

                    if bangumi.votes > 0 {
                        TimelineMetric(icon: "person.2.fill", label: "\(bangumi.votes)", color: .kzTextSecondary)
                    }
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundColor(.kzTextSecondary)
        }
        .padding(12)
        .background(Color.kzSurfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var posterImage: some View {
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
                    .font(.title3)
                    .foregroundColor(.kzTextSecondary)
            }
        }
        .frame(width: 94, height: 126)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct TimelineMetric: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)

            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.kzText)
        }
    }
}

private struct TimelineWeekdayButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isFocused ? Color.kzFocusFill : Color.clear)
            )
            .shadow(
                color: isFocused ? Color.kzFocusGlow : Color.clear,
                radius: isFocused ? 14 : 0,
                x: 0,
                y: isFocused ? 6 : 0
            )
            .scaleEffect(isFocused ? 1.035 : 1.0)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: 0.16), value: isFocused)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private enum TimelineOptionFocus: Hashable {
    case close
    case sort(TimelineSortType)
    case abandoned
    case watched
}

#Preview {
    TimelineView()
}
