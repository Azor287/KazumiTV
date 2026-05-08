//
//  Router.swift
//  KazumiTV
//
//  Navigation router for programmatic navigation
//

import SwiftUI

// MARK: - Navigation Destination
enum NavigationDestination: Hashable {
    case search
    case bangumiDetail(Bangumi, SearchItem?)
    case collectedBangumi(CollectedBangumi)
    case settings
    case pluginRules
    case history
    case timelineDetail(date: String)
    case player(bangumi: Bangumi, episode: Episode)
    case playerSession(PlaybackSession)

    var hidesMainChrome: Bool {
        if case .search = self {
            return true
        }
        if case .bangumiDetail = self {
            return true
        }
        if case .collectedBangumi = self {
            return true
        }
        if case .settings = self {
            return true
        }
        if case .player = self {
            return true
        }
        if case .playerSession = self {
            return true
        }
        return false
    }
}

// MARK: - Router
@MainActor
final class Router: ObservableObject {
    static let shared = Router()

    @Published var path = NavigationPath()
    @Published private(set) var destinations: [NavigationDestination] = []
    @Published private var mainChromeHiddenOverride: Bool?

    var currentSearchItem: SearchItem?

    var hidesMainChrome: Bool {
        if let mainChromeHiddenOverride {
            return mainChromeHiddenOverride
        }

        return destinations.last?.hidesMainChrome == true
    }

    private init() {}

    func navigate(to destination: NavigationDestination) {
        destinations.append(destination)
        path.append(destination)
    }

    func pop() {
        if !path.isEmpty {
            path.removeLast()
        }
        if !destinations.isEmpty {
            destinations.removeLast()
        }
    }

    func popToRoot() {
        path = NavigationPath()
        destinations.removeAll()
        mainChromeHiddenOverride = nil
    }

    func syncToPathCount(_ count: Int) {
        if count < destinations.count {
            destinations.removeLast(destinations.count - count)
        } else if count == 0 {
            destinations.removeAll()
        }
    }

    func setMainChromeHidden(_ hidden: Bool?) {
        mainChromeHiddenOverride = hidden
    }
}
