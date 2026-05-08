//
//  SidebarItem.swift
//  KazumiTV
//
//  Reusable sidebar button component
//

import SwiftUI

struct SidebarItem: View {
    let icon: String
    let label: String?
    let isSelected: Bool
    let action: () -> Void

    init(
        icon: String,
        label: String? = nil,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.label = label
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.title2)
                if let label = label {
                    Text(label)
                        .font(.caption2)
                        .fontWeight(isSelected ? .bold : .regular)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isSelected ? Color.kzPrimary : Color.kzTextSecondary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: label != nil ? 70 : 55)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.kzPrimary.opacity(0.16) : Color.clear)
            )
            .padding(.horizontal, 6)
        }
        .buttonStyle(TVPillButtonStyle())
    }
}

#Preview {
    HStack {
        SidebarItem(icon: "house", label: "推荐", isSelected: true) {}
        SidebarItem(icon: "calendar", label: "时间表", isSelected: false) {}
    }
    .background(Color.kzSurface)
}
