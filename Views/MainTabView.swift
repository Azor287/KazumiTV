//
//  MainTabView.swift
//  KazumiTV
//
//  Main Tab Navigation - tabs: 推荐, 时间表, 追番, 历史
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Tab = .popular
    @ObservedObject private var router = Router.shared
    @FocusState private var focusedTopNavigationItem: TopNavigationFocus?
    private let topNavigationHeight: CGFloat = 84

    enum Tab: Int, CaseIterable, Hashable {
        case popular = 0
        case timeline = 1
        case collect = 2
        case history = 3

        var title: String {
            switch self {
            case .popular: return "推荐"
            case .timeline: return "时间表"
            case .collect: return "追番"
            case .history: return "历史"
            }
        }

        var icon: String {
            switch self {
            case .popular: return "house"
            case .timeline: return "calendar"
            case .collect: return "heart"
            case .history: return "clock.arrow.circlepath"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            MainContent(
                selectedTab: selectedTab,
                router: router,
                focusedTopNavigationItem: $focusedTopNavigationItem,
                topContentInset: topNavigationHeight
            )

            TopNavigation(
                selectedTab: $selectedTab,
                focusedItem: $focusedTopNavigationItem
            )
            .frame(height: topNavigationHeight, alignment: .top)
            .opacity(router.hidesMainChrome ? 0 : 1)
            .disabled(router.hidesMainChrome)
            .accessibilityHidden(router.hidesMainChrome)
            .animation(.easeOut(duration: 0.12), value: router.hidesMainChrome)
        }
        .background(Color.kzBackground)
        .preferredColorScheme(.dark)
    }
}

private enum TopNavigationFocus: Hashable {
    case search
    case tab(MainTabView.Tab)
    case settings
}

// MARK: - Top Navigation
private struct TopNavigation: View {
    @Binding var selectedTab: MainTabView.Tab
    let focusedItem: FocusState<TopNavigationFocus?>.Binding
    @ObservedObject private var router = Router.shared

    var body: some View {
        HStack(spacing: 14) {
            Button {
                router.popToRoot()
                router.navigate(to: .search)
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.kzTextSecondary)
                    .frame(width: 64, height: 56)
            }
            .buttonStyle(TVIconButtonStyle())
            .focused(focusedItem, equals: .search)

            ForEach(MainTabView.Tab.allCases, id: \.rawValue) { tab in
                Button {
                    router.popToRoot()
                    selectedTab = tab
                } label: {
                    TopNavigationItem(
                        icon: tab.icon,
                        title: tab.title,
                        isSelected: selectedTab == tab
                    )
                }
                .buttonStyle(TVPillButtonStyle())
                .focused(focusedItem, equals: .tab(tab))
            }

            Spacer(minLength: 0)

            Button {
                router.popToRoot()
                router.navigate(to: .settings)
            } label: {
                TopNavigationItem(
                    icon: "gearshape",
                    title: "设置",
                    isSelected: false
                )
            }
            .buttonStyle(TVPillButtonStyle())
            .focused(focusedItem, equals: .settings)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color.kzBackground.opacity(0.96),
                    Color.kzBackground.opacity(0.82),
                    Color.kzBackground.opacity(0.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
        .focusSection()
    }
}

private struct TopNavigationItem: View {
    let icon: String
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.headline)

            Text(title)
                .font(.headline)
                .fontWeight(isSelected ? .bold : .semibold)
        }
        .foregroundStyle(isSelected ? Color.kzOnPrimaryContainer : Color.kzTextSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.82)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 18)
        .frame(minWidth: 112, minHeight: 56)
        .background(
            Capsule()
                .fill(isSelected ? Color.kzPrimaryContainer.opacity(0.95) : Color.clear)
        )
    }
}

// MARK: - Main Content
private struct MainContent: View {
    let selectedTab: MainTabView.Tab
    @ObservedObject var router: Router
    let focusedTopNavigationItem: FocusState<TopNavigationFocus?>.Binding
    let topContentInset: CGFloat

    var body: some View {
        NavigationStack(path: $router.path) {
            TabContentView(selectedTab: selectedTab)
                .padding(.top, topContentInset)
                .focusSection()
                .onExitCommand {
                    if !router.destinations.isEmpty {
                        router.pop()
                    } else {
                        focusedTopNavigationItem.wrappedValue = .tab(selectedTab)
                    }
                }
                .navigationDestination(for: NavigationDestination.self) {
                    DestinationView(destination: $0)
                }
        }
        .onChange(of: router.path.count) { _, count in
            router.syncToPathCount(count)
        }
    }
}

// MARK: - Tab Content View
private struct TabContentView: View {
    let selectedTab: MainTabView.Tab

    var body: some View {
        switch selectedTab {
        case .popular:
            HomeView()
        case .timeline:
            TimelineView()
        case .collect:
            CollectView()
        case .history:
            HistoryView(topPadding: 14)
        }
    }
}

// MARK: - Destination View
private struct DestinationView: View {
    let destination: NavigationDestination

    var body: some View {
        switch destination {
        case .search:
            SearchView()
        case .bangumiDetail(let bangumi, let searchItem):
            BangumiDetailView(bangumi: bangumi, searchItem: searchItem)
        case .collectedBangumi(let collected):
            CollectedBangumiDetailView(collected: collected)
        case .settings:
            SettingsView()
        case .pluginRules:
            PluginRulesView()
        case .history:
            HistoryView()
        case .timelineDetail(let date):
            TimelineDetailView(date: date)
        case .player(let bangumi, let episode):
            PlayerView(bangumi: bangumi, episode: episode)
        case .playerSession(let session):
            PlayerView(session: session)
        }
    }
}

#Preview {
    MainTabView()
}
