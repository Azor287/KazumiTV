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
                .task {
                    await initializeStorage()
                }
        }
    }

    private func initializeStorage() async {
        do {
            try await DatabaseManager.shared.setup()
            async let localSync: Void = TopShelfSyncService.syncAll()
            async let remoteSync: Void = TopShelfRemoteSyncService.syncAll()
            _ = await (localSync, remoteSync)
        } catch {
            print("KazumiTVApp: failed to initialize local storage: \(error.localizedDescription)")
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
