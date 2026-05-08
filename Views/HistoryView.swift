//
//  HistoryView.swift
//  KazumiTV
//
//  历史记录页面
//

import SwiftUI
import Combine
import Kingfisher

struct HistoryView: View {
    let topPadding: CGFloat

    @StateObject private var viewModel = HistoryViewModel()
    @ObservedObject private var router = Router.shared
    @Environment(\.resetFocus) private var resetFocus
    @Namespace private var cardFocusScope
    @State private var isEditing = false
    @State private var showClearConfirmation = false
    @State private var playbackErrorMessage: String?
    @State private var loadingHistoryID: String?
    @FocusState private var focusedHistoryID: String?
    @State private var pendingFocusRestoreHistoryID: String?

    init(topPadding: CGFloat = 98) {
        self.topPadding = topPadding
    }

    var body: some View {
        ZStack {
            Color.kzBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                toolbar

                content
            }
            .padding(.top, topPadding)
            .padding(.bottom, 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarHidden(true)
        .onAppear {
            Task {
                await viewModel.loadDataIfNeeded()
                scheduleCardFocusRestore()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchHistoryDidChange).receive(on: DispatchQueue.main)) { _ in
            Task {
                await viewModel.refresh()
                scheduleCardFocusRestore()
            }
        }
        .alert("记录管理", isPresented: $showClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                Task {
                    await clearAll()
                }
            }
        } message: {
            Text("确认要清除所有历史记录吗?")
        }
        .alert("无法继续播放", isPresented: playbackErrorBinding) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(playbackErrorMessage ?? "")
        }
    }

    @ViewBuilder
    private var toolbar: some View {
        if !viewModel.histories.isEmpty {
            HStack(spacing: 14) {
                Text("\(viewModel.histories.count) 条记录")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.kzTextSecondary)

                Spacer()

                Button {
                    isEditing.toggle()
                } label: {
                    Label(isEditing ? "完成" : "编辑", systemImage: isEditing ? "checkmark" : "square.and.pencil")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.kzText)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 54)
                }
                .buttonStyle(TVPillButtonStyle())

                Button {
                    showClearConfirmation = true
                } label: {
                    Label("清空", systemImage: "trash")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.kzText)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 54)
                }
                .buttonStyle(TVPillButtonStyle())
            }
            .padding(.horizontal, 72)
            .padding(.bottom, 18)
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.histories.isEmpty {
            ProgressView()
                .tint(.kzPrimary)
                .scaleEffect(1.35)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.histories.isEmpty {
            emptyState
        } else {
            historyGrid
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 66, weight: .semibold))
                .foregroundStyle(Color.kzTextSecondary.opacity(0.56))

            Text("没有找到历史记录")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Color.kzTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var historyGrid: some View {
        GeometryReader { proxy in
            let contentWidth = min(proxy.size.width - 96, 1540)
            let columns = Array(
                repeating: GridItem(.flexible(), spacing: 16),
                count: columnCount(for: contentWidth)
            )
            let sidePadding = max((proxy.size.width - contentWidth) / 2, 48)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(viewModel.histories) { history in
                        Button {
                            if isEditing {
                                delete(history)
                            } else {
                                pendingFocusRestoreHistoryID = history.id
                                focusedHistoryID = history.id
                                play(history)
                            }
                        } label: {
                            HistoryCardLabel(
                                history: history,
                                isEditing: isEditing,
                                isLoading: loadingHistoryID == history.id
                            )
                        }
                        .buttonStyle(TVCardButtonStyle())
                        .focused($focusedHistoryID, equals: history.id)
                        .disabled(loadingHistoryID != nil && loadingHistoryID != history.id)
                    }
                }
                .padding(.horizontal, sidePadding)
                .padding(.top, 28)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .focusScope(cardFocusScope)
            .focusSection()
        }
    }

    private var playbackErrorBinding: Binding<Bool> {
        Binding(
            get: { playbackErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    playbackErrorMessage = nil
                }
            }
        )
    }

    private func columnCount(for width: CGFloat) -> Int {
        if width >= 1280 {
            return 3
        }
        if width >= 820 {
            return 2
        }
        return 1
    }

    private func play(_ history: History) {
        guard loadingHistoryID == nil else { return }

        loadingHistoryID = history.id
        Task {
            do {
                let session = try await viewModel.makePlaybackSession(for: history)
                loadingHistoryID = nil
                router.navigate(to: .playerSession(session))
            } catch {
                loadingHistoryID = nil
                if let searchItem = history.searchItem {
                    router.navigate(to: .bangumiDetail(history.bangumi, searchItem))
                } else {
                    playbackErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func delete(_ history: History) {
        Task {
            await viewModel.deleteHistory(id: history.id)
            if focusedHistoryID == history.id {
                focusedHistoryID = nil
            }
            if pendingFocusRestoreHistoryID == history.id {
                pendingFocusRestoreHistoryID = nil
            }
            if viewModel.histories.isEmpty {
                isEditing = false
            }
        }
    }

    private func clearAll() async {
        await viewModel.clearAllHistory()
        isEditing = false
        focusedHistoryID = nil
        pendingFocusRestoreHistoryID = nil
    }

    private func scheduleCardFocusRestore() {
        guard !isEditing,
              let targetID = pendingFocusRestoreHistoryID ?? focusedHistoryID,
              viewModel.histories.contains(where: { $0.id == targetID }) else {
            return
        }

        DispatchQueue.main.async {
            focusedHistoryID = targetID
            resetFocus(in: cardFocusScope)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            focusedHistoryID = targetID
            resetFocus(in: cardFocusScope)
        }
    }
}

private struct HistoryCardLabel: View {
    let history: History
    let isEditing: Bool
    let isLoading: Bool
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 14) {
            poster

            VStack(alignment: .leading, spacing: 8) {
                Text(history.bangumiName)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.kzText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Label(history.displayEpisodeName, systemImage: "play.circle")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.kzTextSecondary)
                    .lineLimit(1)

                Label(history.sourceDisplayName, systemImage: "puzzlepiece.extension")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.kzTextSecondary.opacity(0.92))
                    .lineLimit(1)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 7) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.black.opacity(0.24))

                            Capsule()
                                .fill(isEditing ? Color.red.opacity(0.76) : Color.kzPrimary.opacity(0.86))
                                .frame(width: progressWidth(totalWidth: proxy.size.width))
                        }
                    }
                    .frame(height: 6)

                    HStack(spacing: 8) {
                        Text(history.playbackProgressText)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        Text(history.relativeWatchedText)
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.kzTextSecondary.opacity(0.82))
                }
            }

            Spacer(minLength: 0)

            trailingIcon
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 154, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isFocused ? Color.kzSurfaceContainer.opacity(0.96) : Color.kzSurfaceContainerLow.opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isFocused ? Color.kzPrimary.opacity(0.54) : Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private var poster: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.kzCardBackground)

            if let url = history.posterURL {
                KFImage(url)
                    .placeholder {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(Color.kzTextSecondary)
                    }
                    .retry(maxCount: 2, interval: .seconds(1))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "play.rectangle")
                    .font(.title2)
                    .foregroundStyle(Color.kzTextSecondary)
            }
        }
        .frame(width: 82, height: 126)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func progressWidth(totalWidth: CGFloat) -> CGFloat {
        guard history.progressPercentage > 0 else { return 0 }
        return max(6, totalWidth * history.progressPercentage)
    }

    @ViewBuilder
    private var trailingIcon: some View {
        if isLoading {
            ProgressView()
                .tint(.kzPrimary)
                .frame(width: 42, height: 42)
        } else {
            Image(systemName: isEditing ? "trash" : "play.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(isEditing ? Color.red.opacity(0.88) : Color.kzOnPrimaryContainer)
                .frame(width: 46, height: 46)
                .background(
                    Circle()
                        .fill(isEditing ? Color.red.opacity(0.18) : Color.kzPrimaryContainer.opacity(0.88))
                )
        }
    }
}

#Preview {
    HistoryView()
}
