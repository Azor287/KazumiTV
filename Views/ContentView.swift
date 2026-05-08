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
    }

    private func hideStartupSplashAfterDelay() async {
        guard isShowingStartupSplash else { return }

        try? await Task.sleep(nanoseconds: 1_000_000_000)

        guard !Task.isCancelled else { return }

        withAnimation(.easeOut(duration: 0.35)) {
            isShowingStartupSplash = false
        }
    }
}

private struct StartupSplashView: View {
    var body: some View {
        GeometryReader { geometry in
            Image("LaunchScreenImage")
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
