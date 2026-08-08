//
//  ContentView.swift
//  KazumiTV
//
//  Main Content View
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var isShowingStartupSplash = true

    var body: some View {
        ZStack {
            MainTabView()

            if isShowingStartupSplash {
                StartupSplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            await hideStartupSplashAfterDelay()
        }
        .onOpenURL { url in
            openTopShelfURL(url)
        }
    }

    private func hideStartupSplashAfterDelay() async {
        guard isShowingStartupSplash else { return }

        try? await Task.sleep(nanoseconds: 1_000_000_000)

        guard !Task.isCancelled else { return }

        withAnimation(.easeOut(duration: 0.35)) {
            isShowingStartupSplash = false
        }
    }

    private func openTopShelfURL(_ url: URL) {
        guard url.scheme == "kazumitv",
              url.host == "subject",
              let subjectID = Int(url.pathComponents.dropFirst().first ?? "") else {
            return
        }

        Task {
            guard let bangumi = try? await BangumiAPI.shared.getBangumiInfo(id: subjectID) else {
                return
            }
            Router.shared.popToRoot()
            Router.shared.navigate(to: .bangumiDetail(bangumi, nil))
        }
    }
}

private struct StartupSplashView: View {
    var body: some View {
        GeometryReader { geometry in
            Image("LaunchBrandingV2")
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
        .background(Color.kzBackground.ignoresSafeArea())
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
