//
//  TVFocusStyles.swift
//  KazumiTV
//
//  Shared tvOS focus styling for buttons and navigation links.
//

import SwiftUI

struct TVCardButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isFocused ? 1.045 : 1.0)
            .zIndex(isFocused ? 10 : 0)
            .shadow(
                color: isFocused ? Color.kzFocusGlow : Color.clear,
                radius: isFocused ? 18 : 0,
                x: 0,
                y: isFocused ? 8 : 0
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: 0.16), value: isFocused)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct TVPillButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isFocused ? 1.055 : 1.0)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isFocused ? Color.kzFocusFill : Color.clear)
            )
            .shadow(
                color: isFocused ? Color.kzFocusGlow : Color.clear,
                radius: isFocused ? 14 : 0,
                x: 0,
                y: isFocused ? 6 : 0
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.16), value: isFocused)
    }
}

struct TVIconButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: 64, minHeight: 64)
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isFocused ? Color.kzFocusFill : Color.clear)
            )
            .shadow(
                color: isFocused ? Color.kzFocusGlow : Color.clear,
                radius: isFocused ? 14 : 0,
                x: 0,
                y: isFocused ? 6 : 0
            )
            .scaleEffect(isFocused ? 1.075 : 1.0)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.16), value: isFocused)
    }
}
