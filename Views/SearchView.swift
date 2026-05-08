//
//  SearchView.swift
//  KazumiTV
//
//  Search View - Search anime with filters
//

import SwiftUI
import UIKit

struct SearchView: View {
    @ObservedObject private var router = Router.shared
    @StateObject private var viewModel = SearchViewModel()
    @Environment(\.resetFocus) private var resetFocus
    @Namespace private var cardFocusScope
    @FocusState private var searchBarFocused: Bool
    @State private var searchFocusRequestID = 0
    @State private var wantsSearchTextInput = false
    @State private var isSearchFieldEditing = false
    @FocusState private var clearRecentFocused: Bool
    @FocusState private var focusedRecentSearch: String?
    @FocusState private var focusedBangumiID: Int?
    @State private var pendingFocusRestoreBangumiID: Int?
    private let cardFocusOutset: CGFloat = 18

    var body: some View {
        VStack(spacing: 0) {
            // Header with back button and search field
            headerView
                .padding(.horizontal, 16)
                .padding(.top, 16)

            if viewModel.searchText.isEmpty {
                recentSearchesView
            } else {
                searchResultsView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.kzBackground)
        .navigationBarHidden(true)
        .onAppear {
            if canRestoreResultFocus {
                scheduleCardFocusRestore()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    searchBarFocused = true
                }
            }
        }
        .onDisappear {
            searchBarFocused = false
            wantsSearchTextInput = false
            isSearchFieldEditing = false
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: 0) {
            // Search field
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.kzTextSecondary)

                TVSearchTextField(
                    text: $viewModel.searchText,
                    placeholder: "搜索番剧...",
                    focusRequestID: searchFocusRequestID,
                    wantsTextInput: $wantsSearchTextInput,
                    isEditing: $isSearchFieldEditing
                ) {
                    Task {
                        await viewModel.search(query: viewModel.searchText)
                    }
                }
                .frame(height: 44)
                .onSubmit {
                    Task {
                        await viewModel.search(query: viewModel.searchText)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSearchFieldEditing || searchBarFocused ? Color.kzSurfaceContainerLow : Color.kzSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSearchFieldEditing || searchBarFocused ? Color.kzPrimary.opacity(0.75) : Color.clear,
                        lineWidth: 2
                    )
            }
            .focusable(true)
            .focused($searchBarFocused)
            .onTapGesture {
                searchBarFocused = true
                wantsSearchTextInput = true
                searchFocusRequestID += 1
            }
            .onMoveCommand { direction in
                guard direction == .down,
                      viewModel.searchText.isEmpty,
                      let firstRecentSearch = viewModel.recentSearches.first else { return }

                searchBarFocused = false
                wantsSearchTextInput = false
                focusedRecentSearch = firstRecentSearch
            }
        }
        .onExitCommand {
            router.pop()
        }
        .padding(.bottom, 16)
    }

    // MARK: - Recent Searches
    private var recentSearchesView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !viewModel.recentSearches.isEmpty {
                HStack {
                    Text("最近搜索")
                        .font(.headline)
                        .foregroundColor(.kzText)

                    Spacer()

                    Button("清除") {
                        viewModel.clearRecentSearches()
                        clearRecentFocused = false
                    }
                    .font(.subheadline)
                    .foregroundColor(.kzPrimary)
                    .buttonStyle(TVPillButtonStyle())
                    .focused($clearRecentFocused)
                    .onMoveCommand { direction in
                        guard direction == .down || direction == .left else { return }
                        focusedRecentSearch = viewModel.recentSearches.first
                        clearRecentFocused = false
                    }
                }
                .padding(.horizontal, 16)
                .focusSection()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.recentSearches, id: \.self) { search in
                            Button {
                                searchBarFocused = false
                                focusedRecentSearch = search
                                pendingFocusRestoreBangumiID = nil
                                Task {
                                    viewModel.searchText = search
                                    await viewModel.search(query: search)
                                    DispatchQueue.main.async {
                                        focusedBangumiID = viewModel.searchResults.first?.id
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "clock")
                                        .foregroundColor(.kzTextSecondary)
                                    Text(search)
                                        .foregroundColor(.kzText)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(TVPillButtonStyle())
                            .focused($focusedRecentSearch, equals: search)
                            .onMoveCommand { direction in
                                guard search == viewModel.recentSearches.first,
                                      direction == .up || direction == .right else { return }

                                focusedRecentSearch = nil
                                clearRecentFocused = true
                            }
                        }
                    }
                    .focusSection()
                }
            } else {
                emptyStateView(
                    icon: "magnifyingglass",
                    title: "搜索番剧",
                    subtitle: "输入关键词搜索你喜欢的番剧"
                )
            }

            Spacer()
        }
        .padding(.top, 16)
    }

    // MARK: - Search Results
    private var searchResultsView: some View {
        GeometryReader { geometry in
            let columnCount = calculateColumnCount(width: geometry.size.width)
            let cardWidth = (geometry.size.width - 48 - CGFloat(columnCount - 1) * 8) / CGFloat(columnCount)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !viewModel.searchResults.isEmpty {
                        sectionHeader("番剧结果", isLoading: viewModel.isSearching)

                        LazyVStack(spacing: 8) {
                            ForEach(Array(viewModel.searchResults.chunked(into: columnCount).enumerated()), id: \.offset) { _, rowItems in
                                let titleHeight = rowTitleHeight(for: rowItems, cardWidth: cardWidth)
                                let cardHeight = cardWidth / 0.65 + titleHeight
                                let rowHeight = cardHeight + cardFocusOutset

                                HStack(spacing: 8) {
                                    ForEach(rowItems) { bangumi in
                                        Button {
                                            pendingFocusRestoreBangumiID = bangumi.id
                                            focusedBangumiID = bangumi.id
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
                            }
                        }
                    } else if viewModel.isSearching {
                        sectionHeader("番剧结果", isLoading: true)
                    }

                    if !viewModel.isSearching &&
                        viewModel.searchResults.isEmpty {
                        emptyResultsView
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
            }
            .focusScope(cardFocusScope)
            .focusSection()
        }
    }

    private func calculateColumnCount(width: CGFloat) -> Int {
        if width > 1200 { return 6 }
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

    private func sectionHeader(_ title: String, isLoading: Bool) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundColor(.kzText)

            if isLoading {
                ProgressView()
                    .tint(.kzPrimary)
                    .scaleEffect(0.72)
            }

            Spacer()
        }
    }

    // MARK: - Empty Results
    private var emptyResultsView: some View {
        emptyStateView(
            icon: "magnifyingglass",
            title: "未找到结果",
            subtitle: "试试其他关键词"
        )
    }

    private var canRestoreResultFocus: Bool {
        guard let targetID = pendingFocusRestoreBangumiID ?? focusedBangumiID else {
            return false
        }

        return viewModel.searchResults.contains(where: { $0.id == targetID })
    }

    private func scheduleCardFocusRestore() {
        guard let targetID = pendingFocusRestoreBangumiID ?? focusedBangumiID,
              viewModel.searchResults.contains(where: { $0.id == targetID }) else {
            return
        }

        searchBarFocused = false
        wantsSearchTextInput = false

        DispatchQueue.main.async {
            focusedBangumiID = targetID
            resetFocus(in: cardFocusScope)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            focusedBangumiID = targetID
            resetFocus(in: cardFocusScope)
        }
    }

    // MARK: - Empty State
    private func emptyStateView(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(.kzTextSecondary)
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.kzText)
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.kzTextSecondary)
            Spacer()
        }
    }
}

private struct TVSearchTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let focusRequestID: Int
    @Binding var wantsTextInput: Bool
    @Binding var isEditing: Bool
    let onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.backgroundColor = .clear
        textField.borderStyle = .none
        textField.textColor = UIColor(Color.kzText)
        textField.tintColor = UIColor(Color.kzPrimary)
        textField.font = UIFont.preferredFont(forTextStyle: .title3)
        textField.returnKeyType = .search
        textField.keyboardAppearance = .dark
        textField.clearButtonMode = .whileEditing
        textField.autocorrectionType = .no
        textField.delegate = context.coordinator
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: UIColor(Color.kzTextSecondary).withAlphaComponent(0.62),
                .font: UIFont.preferredFont(forTextStyle: .title3)
            ]
        )
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange(_:)),
            for: .editingChanged
        )

        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }

        context.coordinator.isEditing = $isEditing
        context.coordinator.wantsTextInput = $wantsTextInput

        if focusRequestID != context.coordinator.lastFocusRequestID,
           uiView.window != nil {
            context.coordinator.lastFocusRequestID = focusRequestID
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        } else if !wantsTextInput, uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.resignFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, wantsTextInput: $wantsTextInput, isEditing: $isEditing, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String
        var wantsTextInput: Binding<Bool>
        var isEditing: Binding<Bool>
        var lastFocusRequestID = 0
        private let onSubmit: () -> Void

        init(
            text: Binding<String>,
            wantsTextInput: Binding<Bool>,
            isEditing: Binding<Bool>,
            onSubmit: @escaping () -> Void
        ) {
            _text = text
            self.wantsTextInput = wantsTextInput
            self.isEditing = isEditing
            self.onSubmit = onSubmit
        }

        @objc func textDidChange(_ textField: UITextField) {
            text = textField.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            onSubmit()
            wantsTextInput.wrappedValue = false
            textField.resignFirstResponder()
            return true
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            isEditing.wrappedValue = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            wantsTextInput.wrappedValue = false
            isEditing.wrappedValue = false
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            let currentText = textField.text ?? ""
            guard let textRange = Range(range, in: currentText) else { return true }

            text = currentText.replacingCharacters(in: textRange, with: string)
            return true
        }
    }
}

#Preview {
    NavigationStack {
        SearchView()
    }
    .preferredColorScheme(.dark)
}
