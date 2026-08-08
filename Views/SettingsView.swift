//
//  SettingsView.swift
//  KazumiTV
//
//  设置页面
//

import Kingfisher
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var router = Router.shared

    @State private var privateWebResolverEnabled: Bool = SettingsRepository.shared.privateWebResolverEnabled
    @State private var playResume: Bool = SettingsRepository.shared.playResume
    @State private var autoPlay: Bool = SettingsRepository.shared.autoPlay
    @State private var autoPlayNext: Bool = SettingsRepository.shared.autoPlayNext
    @State private var danmakuEnabled: Bool = SettingsRepository.shared.danmakuEnabledByDefault
    @State private var danmakuOpacity: Double = SettingsRepository.shared.danmakuOpacity
    @State private var danmakuFontSize: Double = SettingsRepository.shared.danmakuFontSize
    @State private var danmakuTop: Bool = SettingsRepository.shared.danmakuTop
    @State private var danmakuScroll: Bool = SettingsRepository.shared.danmakuScroll
    @State private var danmakuBottom: Bool = SettingsRepository.shared.danmakuBottom
    @State private var privateMode: Bool = SettingsRepository.shared.privateMode
    @State private var topShelfSource: TopShelfSource = SettingsRepository.shared.topShelfSource

    @State private var isClearingHistory = false
    @State private var noticeText: String?
    @State private var showClearHistoryConfirmation = false
    @State private var showResetConfirmation = false
    @FocusState private var focusedSetting: SettingsFocus?

    private enum SettingsFocus: Hashable {
        case privateWebResolverEnabled
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                localResolverSection
                playbackSection
                danmakuSection
                topShelfSection
                dataSection
                aboutSection
            }
            .padding(.horizontal, 72)
            .padding(.top, 26)
            .padding(.bottom, 72)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.kzBackground.ignoresSafeArea())
        .navigationBarHidden(true)
        .overlay(alignment: .topTrailing) {
            if let noticeText {
                Text(noticeText)
                    .font(.headline)
                    .foregroundColor(.kzOnPrimaryContainer)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.kzPrimaryContainer.opacity(0.92), in: Capsule())
                    .padding(.top, 24)
                    .padding(.trailing, 72)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .onExitCommand {
            closeSettings()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                focusedSetting = .privateWebResolverEnabled
            }
        }
        .onDisappear {
            focusedSetting = nil
        }
        .alert("清除观看历史", isPresented: $showClearHistoryConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                clearHistory()
            }
        } message: {
            Text("观看历史会从本机删除。")
        }
        .alert("恢复默认设置", isPresented: $showResetConfirmation) {
            Button("取消", role: .cancel) {}
            Button("恢复", role: .destructive) {
                resetSettings()
            }
        } message: {
            Text("播放、弹幕、隐身和本机解析设置会恢复为默认值。")
        }
    }

    private var localResolverSection: some View {
        settingsSection(title: "本机解析", subtitle: "搜索、动态网页解析和 HLS 转发均在 Apple TV 上完成") {
            toggleRow(
                title: "动态网页解析",
                subtitle: "原生解析失败后使用本机隐藏网页运行时；关闭后只解析静态页面",
                icon: "safari",
                isOn: $privateWebResolverEnabled
            ) { newValue in
                SettingsRepository.shared.privateWebResolverEnabled = newValue
                showNotice(newValue ? "已启用本机动态网页解析" : "已仅保留静态页面解析")
            }
            .focused($focusedSetting, equals: .privateWebResolverEnabled)
        }
    }

    private var playbackSection: some View {
        settingsSection(title: "播放设置", subtitle: "对播放器行为立即生效") {
            toggleRow(
                title: "自动播放",
                subtitle: "进入播放页后自动开始播放",
                icon: "play.circle",
                isOn: $autoPlay
            ) { newValue in
                SettingsRepository.shared.autoPlay = newValue
            }

            settingsDivider

            toggleRow(
                title: "自动跳转",
                subtitle: "从上次观看进度继续播放",
                icon: "arrow.counterclockwise.circle",
                isOn: $playResume
            ) { newValue in
                SettingsRepository.shared.playResume = newValue
            }

            settingsDivider

            toggleRow(
                title: "自动连播",
                subtitle: "当前集结束后播放下一集",
                icon: "forward.end",
                isOn: $autoPlayNext
            ) { newValue in
                SettingsRepository.shared.autoPlayNext = newValue
            }

            settingsDivider

            toggleRow(
                title: "隐身模式",
                subtitle: "开启后不写入观看历史",
                icon: "eye.slash",
                isOn: $privateMode
            ) { newValue in
                SettingsRepository.shared.privateMode = newValue
            }
        }
    }

    private var danmakuSection: some View {
        settingsSection(title: "弹幕设置", subtitle: "控制默认显示状态和弹幕样式") {
            toggleRow(
                title: "默认开启弹幕",
                subtitle: "进入播放页时自动显示弹幕",
                icon: "captions.bubble",
                isOn: $danmakuEnabled
            ) { newValue in
                SettingsRepository.shared.danmakuEnabledByDefault = newValue
            }

            settingsDivider

            stepperRow(
                title: "弹幕透明度",
                subtitle: "当前 \(Int(danmakuOpacity * 100))%",
                icon: "circle.lefthalf.filled",
                valueText: "\(Int(danmakuOpacity * 100))%",
                canDecrease: danmakuOpacity > 0.2,
                canIncrease: danmakuOpacity < 1.0,
                decrease: {
                    danmakuOpacity = max(0.2, (danmakuOpacity - 0.1).rounded(toPlaces: 1))
                    SettingsRepository.shared.danmakuOpacity = danmakuOpacity
                },
                increase: {
                    danmakuOpacity = min(1.0, (danmakuOpacity + 0.1).rounded(toPlaces: 1))
                    SettingsRepository.shared.danmakuOpacity = danmakuOpacity
                }
            )

            settingsDivider

            stepperRow(
                title: "弹幕字体大小",
                subtitle: "当前 \(Int(danmakuFontSize))",
                icon: "textformat.size",
                valueText: "\(Int(danmakuFontSize))",
                canDecrease: danmakuFontSize > 14,
                canIncrease: danmakuFontSize < 32,
                decrease: {
                    danmakuFontSize = max(14, danmakuFontSize - 2)
                    SettingsRepository.shared.danmakuFontSize = danmakuFontSize
                },
                increase: {
                    danmakuFontSize = min(32, danmakuFontSize + 2)
                    SettingsRepository.shared.danmakuFontSize = danmakuFontSize
                }
            )

            settingsDivider

            toggleRow(
                title: "顶部弹幕",
                subtitle: "允许顶部固定弹幕",
                icon: "arrow.up.to.line.compact",
                isOn: $danmakuTop
            ) { newValue in
                SettingsRepository.shared.danmakuTop = newValue
            }

            settingsDivider

            toggleRow(
                title: "滚动弹幕",
                subtitle: "允许横向滚动弹幕",
                icon: "arrow.right",
                isOn: $danmakuScroll
            ) { newValue in
                SettingsRepository.shared.danmakuScroll = newValue
            }

            settingsDivider

            toggleRow(
                title: "底部弹幕",
                subtitle: "允许底部固定弹幕",
                icon: "arrow.down.to.line.compact",
                isOn: $danmakuBottom
            ) { newValue in
                SettingsRepository.shared.danmakuBottom = newValue
            }
        }
    }

    private var dataSection: some View {
        settingsSection(title: "数据", subtitle: "本机缓存和观看记录") {
            actionRow(
                title: "规则管理",
                subtitle: "更新、编辑、测试、分享、删除、排序和添加资源规则",
                icon: "puzzlepiece.extension",
                isBusy: false
            ) {
                Router.shared.navigate(to: .pluginRules)
            }

            settingsDivider

            actionRow(
                title: "清除图片缓存",
                subtitle: "清理海报缓存，不影响收藏和历史",
                icon: "photo.stack",
                isBusy: false
            ) {
                clearImageCache()
            }

            settingsDivider

            actionRow(
                title: "清除观看历史",
                subtitle: "删除本机播放记录",
                icon: "trash",
                isBusy: isClearingHistory,
                isDestructive: true
            ) {
                showClearHistoryConfirmation = true
            }

            settingsDivider

            actionRow(
                title: "恢复默认设置",
                subtitle: "还原播放、弹幕、外部解析和隐身设置",
                icon: "arrow.counterclockwise",
                isBusy: false,
                isDestructive: true
            ) {
                showResetConfirmation = true
            }
        }
    }

    private var topShelfSection: some View {
        settingsSection(title: "Apple TV 桌面", subtitle: "选择聚焦 KazumiTV 图标时顶部轮播的内容") {
            Menu {
                ForEach(TopShelfSource.allCases) { source in
                    Button {
                        topShelfSource = source
                        SettingsRepository.shared.topShelfSource = source
                        showNotice("顶部轮播已切换为\(source.title)")
                    } label: {
                        Label(source.title, systemImage: source == topShelfSource ? "checkmark" : sourceIcon(source))
                    }
                }
            } label: {
                settingsRowContent(
                    title: "顶部轮播内容",
                    subtitle: topShelfSource.subtitle,
                    icon: "rectangle.stack"
                ) {
                    HStack(spacing: 10) {
                        Text(topShelfSource.title)
                            .font(.headline.weight(.bold))
                            .foregroundColor(.kzText)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.kzTextSecondary)
                    }
                }
            }
            .buttonStyle(SettingsRowButtonStyle())
        }
    }

    private var aboutSection: some View {
        settingsSection(title: "关于", subtitle: nil) {
            HStack(spacing: 18) {
                Image(systemName: "appletv")
                    .font(.title2)
                    .foregroundColor(.kzPrimary)
                    .frame(width: 42)

                VStack(alignment: .leading, spacing: 5) {
                    Text("KazumiTV")
                        .font(.headline)
                        .foregroundColor(.kzText)

                    Text(appVersionText)
                        .font(.subheadline)
                        .foregroundColor(.kzTextSecondary)

                    Text("注意：此项目与 Kazumi 并非同一作者，为经过原作者同意开发的 Apple TV 移植版本。")
                        .font(.subheadline)
                        .foregroundColor(.kzTextSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
        }
    }

    private var settingsDivider: some View {
        Divider()
            .background(Color.kzTextSecondary.opacity(0.14))
            .padding(.leading, 82)
    }

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version?.isEmpty == false ? version : nil, build?.isEmpty == false ? build : nil) {
        case let (.some(version), .some(build)):
            return "版本 \(version) (\(build))"
        case let (.some(version), .none):
            return "版本 \(version)"
        case let (.none, .some(build)):
            return "构建 \(build)"
        case (.none, .none):
            return "版本未知"
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        subtitle: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.kzText)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.kzTextSecondary)
                }
            }
            .padding(.horizontal, 6)

            VStack(spacing: 0) {
                content()
            }
            .background(Color.kzSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.kzTextSecondary.opacity(0.08), lineWidth: 1)
            )
        }
        .focusSection()
    }

    private func toggleRow(
        title: String,
        subtitle: String,
        icon: String,
        isOn: Binding<Bool>,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        Button {
            isOn.wrappedValue.toggle()
            onChange(isOn.wrappedValue)
        } label: {
            settingsRowContent(title: title, subtitle: subtitle, icon: icon) {
                Text(isOn.wrappedValue ? "开" : "关")
                    .font(.headline.weight(.bold))
                    .foregroundColor(isOn.wrappedValue ? .kzOnPrimaryContainer : .kzTextSecondary)
                    .frame(width: 74, height: 38)
                    .background(
                        Capsule()
                            .fill(isOn.wrappedValue ? Color.kzPrimaryContainer : Color.kzSurfaceContainer)
                    )
            }
        }
        .buttonStyle(SettingsRowButtonStyle())
    }

    private func actionRow(
        title: String,
        subtitle: String,
        icon: String,
        isBusy: Bool,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            settingsRowContent(title: title, subtitle: subtitle, icon: icon, iconColor: isDestructive ? .red : .kzPrimary) {
                if isBusy {
                    ProgressView()
                        .tint(.kzPrimary)
                        .frame(width: 42, height: 42)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .foregroundColor(.kzTextSecondary)
                        .frame(width: 42, height: 42)
                }
            }
        }
        .buttonStyle(SettingsRowButtonStyle())
    }

    private func stepperRow(
        title: String,
        subtitle: String,
        icon: String,
        valueText: String,
        canDecrease: Bool,
        canIncrease: Bool,
        decrease: @escaping () -> Void,
        increase: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 18) {
            rowIcon(icon, color: .kzPrimary)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.kzText)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.kzTextSecondary)
            }

            Spacer(minLength: 20)

            Button(action: decrease) {
                Image(systemName: "minus")
                    .font(.headline.weight(.bold))
                    .foregroundColor(canDecrease ? .kzText : .kzTextSecondary.opacity(0.5))
                    .frame(width: 52, height: 44)
            }
            .disabled(!canDecrease)
            .buttonStyle(TVIconButtonStyle())

            Text(valueText)
                .font(.headline.weight(.bold))
                .foregroundColor(.kzText)
                .frame(width: 72)

            Button(action: increase) {
                Image(systemName: "plus")
                    .font(.headline.weight(.bold))
                    .foregroundColor(canIncrease ? .kzText : .kzTextSecondary.opacity(0.5))
                    .frame(width: 52, height: 44)
            }
            .disabled(!canIncrease)
            .buttonStyle(TVIconButtonStyle())
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    private func settingsRowContent<Trailing: View>(
        title: String,
        subtitle: String,
        icon: String,
        iconColor: Color = .kzPrimary,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 18) {
            rowIcon(icon, color: iconColor)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.kzText)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.kzTextSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 20)

            trailing()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .contentShape(Rectangle())
    }

    private func rowIcon(_ icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.title3.weight(.semibold))
            .foregroundColor(color)
            .frame(width: 42, height: 42)
            .background(Color.kzSurfaceContainer, in: RoundedRectangle(cornerRadius: 9))
    }

    private func clearImageCache() {
        ImageCache.default.clearMemoryCache()
        ImageCache.default.clearDiskCache {
            Task { @MainActor in
                showNotice("图片缓存已清除")
            }
        }
    }

    private func clearHistory() {
        isClearingHistory = true

        Task {
            do {
                try await HistoryRepository.shared.clearAllHistory()
                await MainActor.run {
                    isClearingHistory = false
                    showNotice("观看历史已清除")
                }
            } catch {
                await MainActor.run {
                    isClearingHistory = false
                    showNotice("清除失败")
                }
            }
        }
    }

    private func resetSettings() {
        SettingsRepository.shared.resetToDefaults()
        reloadFromSettings()
        showNotice("已恢复默认设置")
    }

    private func closeSettings() {
        if router.destinations.last == .settings {
            router.pop()
        } else {
            dismiss()
        }
    }

    private func reloadFromSettings() {
        privateWebResolverEnabled = SettingsRepository.shared.privateWebResolverEnabled
        playResume = SettingsRepository.shared.playResume
        autoPlay = SettingsRepository.shared.autoPlay
        autoPlayNext = SettingsRepository.shared.autoPlayNext
        danmakuEnabled = SettingsRepository.shared.danmakuEnabledByDefault
        danmakuOpacity = SettingsRepository.shared.danmakuOpacity
        danmakuFontSize = SettingsRepository.shared.danmakuFontSize
        danmakuTop = SettingsRepository.shared.danmakuTop
        danmakuScroll = SettingsRepository.shared.danmakuScroll
        danmakuBottom = SettingsRepository.shared.danmakuBottom
        privateMode = SettingsRepository.shared.privateMode
        topShelfSource = SettingsRepository.shared.topShelfSource
    }

    private func sourceIcon(_ source: TopShelfSource) -> String {
        switch source {
        case .seasonal: return "sparkles.tv"
        case .recentUpdates: return "clock.arrow.circlepath"
        case .favorites: return "heart"
        case .history: return "play.rectangle.on.rectangle"
        }
    }

    private func showNotice(_ text: String) {
        withAnimation(.easeOut(duration: 0.18)) {
            noticeText = text
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard noticeText == text else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                noticeText = nil
            }
        }
    }
}

private struct SettingsRowButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isFocused ? Color.kzFocusFill : Color.clear)
            )
            .shadow(
                color: isFocused ? Color.kzFocusGlow : Color.clear,
                radius: isFocused ? 12 : 0,
                x: 0,
                y: isFocused ? 5 : 0
            )
            .scaleEffect(isFocused ? 1.012 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: 0.14), value: isFocused)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

#Preview {
    SettingsView()
        .preferredColorScheme(.dark)
}
