//
//  TimelineDetailView.swift
//  KazumiTV
//
//  Timeline Detail View - All anime airing on a specific date
//

import SwiftUI

struct TimelineDetailView: View {
    let date: String
    @StateObject private var viewModel = TimelineDetailViewModel()
    @ObservedObject private var router = Router.shared
    @Environment(\.resetFocus) private var resetFocus
    @Namespace private var cardFocusScope
    @FocusState private var focusedBangumiID: Int?
    @State private var pendingFocusRestoreBangumiID: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Date header
                HStack {
                    Text(date)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.kzText)

                    Spacer()

                    Text("\(viewModel.bangumis.count)部番剧")
                        .font(.subheadline)
                        .foregroundColor(.kzTextSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                        .tint(.kzPrimary)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else if viewModel.bangumis.isEmpty {
                    emptyView
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.bangumis) { bangumi in
                            Button {
                                pendingFocusRestoreBangumiID = bangumi.id
                                focusedBangumiID = bangumi.id
                                router.navigate(to: .bangumiDetail(bangumi, nil))
                            } label: {
                                TimelineBangumiRow(bangumi: bangumi)
                            }
                            .buttonStyle(TVCardButtonStyle())
                            .focused($focusedBangumiID, equals: bangumi.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .focusScope(cardFocusScope)
                    .focusSection()
                }
            }
            .padding(.bottom, 16)
        }
        .background(Color.kzBackground)
        .navigationTitle(date)
        .task {
            await viewModel.loadBangumisIfNeeded(for: date)
            scheduleCardFocusRestore()
        }
        .onAppear {
            scheduleCardFocusRestore()
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 50))
                .foregroundColor(.kzTextSecondary)
            Text("当天没有待播番剧")
                .font(.headline)
                .foregroundColor(.kzTextSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func scheduleCardFocusRestore() {
        guard let targetID = pendingFocusRestoreBangumiID ?? focusedBangumiID,
              viewModel.bangumis.contains(where: { $0.id == targetID }) else {
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

// MARK: - ViewModel
@MainActor
class TimelineDetailViewModel: ObservableObject {
    @Published var bangumis: [Bangumi] = []
    @Published var isLoading = false
    @Published var error: Error?

    private let bangumiAPI = BangumiAPI.shared
    private var hasLoadedData = false

    func loadBangumisIfNeeded(for date: String) async {
        guard !hasLoadedData, !isLoading else { return }
        await loadBangumis(for: date)
    }

    func loadBangumis(for date: String) async {
        isLoading = true
        // Parse date and find weekday
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        guard let parsedDate = formatter.date(from: date) else {
            isLoading = false
            return
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = formatter.timeZone ?? .current
        let weekday = calendar.component(.weekday, from: parsedDate)
        let weekdayIndex = (weekday == 1 ? 7 : weekday - 1) - 1

        do {
            let calendarResult = try await bangumiAPI.getCalendar()
            if weekdayIndex >= 0 && weekdayIndex < calendarResult.count {
                bangumis = calendarResult[weekdayIndex]
                hasLoadedData = true
            }
        } catch {
            self.error = error
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        TimelineDetailView(date: "2024-04-01")
    }
    .preferredColorScheme(.dark)
}
