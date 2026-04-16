//
//  KazumiTVApp.swift
//  KazumiTV
//
//  tvOS App Entry Point
//

import SwiftUI

@main
struct KazumiTVApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}

// MARK: - App State
final class AppState: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    let videoService: VideoServiceProtocol

    init() {
        self.videoService = VideoService()
    }
}
