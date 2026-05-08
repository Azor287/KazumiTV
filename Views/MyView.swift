//
//  MyView.swift
//  KazumiTV
//
//  我的页面
//

import SwiftUI

struct MyView: View {
    @ObservedObject private var router = Router.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("我的")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.kzText)

                Spacer()
            }

            HStack(spacing: 16) {
                profileAction(title: "观看历史", icon: "clock.arrow.circlepath") {
                    router.navigate(to: .history)
                }

                profileAction(title: "设置", icon: "gearshape") {
                    router.navigate(to: .settings)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.kzBackground)
    }

    private func profileAction(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.kzPrimary)

                Text(title)
                    .font(.headline)
                    .foregroundColor(.kzText)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.kzTextSecondary)
            }
            .padding(18)
            .frame(width: 300)
            .background(Color.kzSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(TVCardButtonStyle())
    }
}

#Preview {
    MyView()
}
