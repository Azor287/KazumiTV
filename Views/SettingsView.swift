//
//  SettingsView.swift
//  KazumiTV
//
//  设置页面
//

import Kingfisher
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var router = Router.shared

    @State private var serverURL: String = SettingsRepository.shared.serverProxyURL
    @State private var serverEnabled: Bool = SettingsRepository.shared.serverProxyEnabled
    @State private var playResume: Bool = SettingsRepository.shared.playResume
    @State private var autoPlay: Bool = SettingsRepository.shared.autoPlay
    @State private var autoPlayNext: Bool = SettingsRepository.shared.autoPlayNext
    @State private var defaultSuperResolutionMode: SuperResolutionMode = SettingsRepository.shared.defaultSuperResolutionMode
    @State private var superResolutionPerformanceWarningEnabled: Bool = !SettingsRepository.shared.superResolutionPerformanceWarningHidden
    @State private var danmakuEnabled: Bool = SettingsRepository.shared.danmakuEnabledByDefault
    @State private var danmakuOpacity: Double = SettingsRepository.shared.danmakuOpacity
    @State private var danmakuFontSize: Double = SettingsRepository.shared.danmakuFontSize
    @State private var danmakuTop: Bool = SettingsRepository.shared.danmakuTop
    @State private var danmakuScroll: Bool = SettingsRepository.shared.danmakuScroll
    @State private var danmakuBottom: Bool = SettingsRepository.shared.danmakuBottom
    @State private var privateMode: Bool = SettingsRepository.shared.privateMode

    @State private var isTestingConnection = false
    @State private var isClearingHistory = false
    @State private var connectionStatus: ConnectionStatus = .unknown
    @State private var noticeText: String?
    @State private var showClearHistoryConfirmation = false
    @State private var showResetConfirmation = false
    @State private var serverURLFocusRequestID = 0
    @State private var wantsServerURLTextInput = false
    @State private var isServerURLEditing = false
    @FocusState private var focusedSetting: SettingsFocus?

    private enum SettingsFocus: Hashable {
        case serverProxyEnabled
        case serverURL
    }

    enum ConnectionStatus {
        case unknown, testing, success, failed

        var text: String {
            switch self {
            case .unknown: return ""
            case .testing: return "测试中"
            case .success: return "连接成功"
            case .failed: return "连接失败"
            }
        }

        var color: Color {
            switch self {
            case .unknown: return .kzTextSecondary
            case .testing: return .yellow
            case .success: return .green
            case .failed: return .red
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                serverProxySection
                playbackSection
                danmakuSection
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
                focusedSetting = .serverProxyEnabled
            }
        }
        .onDisappear {
            focusedSetting = nil
            wantsServerURLTextInput = false
            isServerURLEditing = false
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
            Text("播放、超分辨率、弹幕、隐身和服务器代理设置会恢复为默认值。")
        }
    }

    private var serverProxySection: some View {
        settingsSection(title: "服务器代理", subtitle: "tvOS 使用本地代理解析播放地址") {
            toggleRow(
                title: "启用服务器代理",
                subtitle: "关闭后只使用本地规则解析，部分站点无法播放",
                icon: "network",
                isOn: $serverEnabled
            ) { newValue in
                SettingsRepository.shared.serverProxyEnabled = newValue
                showNotice(newValue ? "已启用服务器代理" : "已关闭服务器代理")
            }
            .focused($focusedSetting, equals: .serverProxyEnabled)

            settingsDivider

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("服务器地址", systemImage: "server.rack")
                            .font(.headline)
                            .foregroundColor(.kzText)

                        Text("模拟器可用 127.0.0.1；真机填写运行服务器的 Mac 局域网地址")
                            .font(.subheadline)
                            .foregroundColor(.kzTextSecondary)
                    }

                    Spacer(minLength: 24)

                    connectionStatusView
                }

                HStack(spacing: 14) {
                    let isServerURLActive = focusedSetting == .serverURL || isServerURLEditing

                    HStack(spacing: 0) {
                        TVServerURLTextField(
                            text: $serverURL,
                            placeholder: "http://127.0.0.1:5001",
                            focusRequestID: serverURLFocusRequestID,
                            wantsTextInput: $wantsServerURLTextInput,
                            isEditing: $isServerURLEditing,
                            isActive: isServerURLActive,
                            onSubmit: saveServerURL
                        )
                        .frame(height: 28)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 58)
                    .background(
                        isServerURLActive
                            ? Color.kzPrimaryContainer.opacity(0.78)
                            : Color.kzSurfaceContainerLow
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isServerURLActive
                                    ? Color.kzPrimary.opacity(0.82)
                                    : Color.kzTextSecondary.opacity(0.18),
                                lineWidth: isServerURLActive ? 2 : 1
                            )
                    )
                    .shadow(
                        color: isServerURLActive ? Color.kzFocusGlow : Color.clear,
                        radius: isServerURLActive ? 16 : 0,
                        x: 0,
                        y: isServerURLActive ? 6 : 0
                    )
                    .focusable(true)
                    .focusEffectDisabled()
                    .focused($focusedSetting, equals: .serverURL)
                    .onTapGesture {
                        focusedSetting = .serverURL
                        wantsServerURLTextInput = true
                        serverURLFocusRequestID += 1
                    }
                    .onChange(of: serverURL) { _, _ in
                        connectionStatus = .unknown
                    }
                    .animation(.easeOut(duration: 0.16), value: isServerURLActive)
                    .onMoveCommand { direction in
                        if direction == .right && !isServerURLEditing {
                            wantsServerURLTextInput = false
                        }
                    }

                    Button {
                        saveServerURL()
                        testConnection()
                    } label: {
                        HStack(spacing: 8) {
                            if isTestingConnection {
                                ProgressView()
                                    .tint(.kzOnPrimaryContainer)
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.headline)
                            }

                            Text(isTestingConnection ? "测试中" : "测试")
                                .font(.headline)
                        }
                        .foregroundColor(.kzOnPrimaryContainer)
                        .frame(width: 132, height: 58)
                    }
                    .disabled(serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTestingConnection)
                    .buttonStyle(TVPillButtonStyle())
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
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

            stepperRow(
                title: "默认超分辨率",
                subtitle: defaultSuperResolutionMode.settingsDescription,
                icon: "sparkles",
                valueText: defaultSuperResolutionMode.title,
                canDecrease: defaultSuperResolutionMode.previous != nil,
                canIncrease: defaultSuperResolutionMode.next != nil,
                decrease: {
                    guard let previous = defaultSuperResolutionMode.previous else { return }
                    defaultSuperResolutionMode = previous
                    SettingsRepository.shared.defaultSuperResolutionMode = previous
                },
                increase: {
                    guard let next = defaultSuperResolutionMode.next else { return }
                    defaultSuperResolutionMode = next
                    SettingsRepository.shared.defaultSuperResolutionMode = next
                }
            )

            settingsDivider

            toggleRow(
                title: "超分性能提示",
                subtitle: "首次切到轻量增强或 M/S 权重超分时提醒可能卡顿",
                icon: "exclamationmark.triangle",
                isOn: $superResolutionPerformanceWarningEnabled
            ) { newValue in
                SettingsRepository.shared.superResolutionPerformanceWarningHidden = !newValue
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
                subtitle: "还原播放、超分辨率、弹幕、代理和隐身设置",
                icon: "arrow.counterclockwise",
                isBusy: false,
                isDestructive: true
            ) {
                showResetConfirmation = true
            }
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

    private var connectionStatusView: some View {
        Group {
            if connectionStatus != .unknown {
                HStack(spacing: 8) {
                    Circle()
                        .fill(connectionStatus.color)
                        .frame(width: 9, height: 9)

                    Text(connectionStatus.text)
                        .font(.headline)
                        .foregroundColor(connectionStatus.color)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(connectionStatus.color.opacity(0.12), in: Capsule())
            }
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

    private func saveServerURL() {
        let normalized = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        serverURL = normalized.isEmpty ? "http://127.0.0.1:5001" : normalized
        SettingsRepository.shared.serverProxyURL = serverURL
    }

    private func testConnection() {
        isTestingConnection = true
        connectionStatus = .testing

        Task {
            let isHealthy = await ServerAPI.shared.healthCheck()
            await MainActor.run {
                isTestingConnection = false
                connectionStatus = isHealthy ? .success : .failed
                showNotice(isHealthy ? "服务器连接成功" : "服务器连接失败")
            }
        }
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
        connectionStatus = .unknown
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
        serverURL = SettingsRepository.shared.serverProxyURL
        serverEnabled = SettingsRepository.shared.serverProxyEnabled
        playResume = SettingsRepository.shared.playResume
        autoPlay = SettingsRepository.shared.autoPlay
        autoPlayNext = SettingsRepository.shared.autoPlayNext
        defaultSuperResolutionMode = SettingsRepository.shared.defaultSuperResolutionMode
        superResolutionPerformanceWarningEnabled = !SettingsRepository.shared.superResolutionPerformanceWarningHidden
        danmakuEnabled = SettingsRepository.shared.danmakuEnabledByDefault
        danmakuOpacity = SettingsRepository.shared.danmakuOpacity
        danmakuFontSize = SettingsRepository.shared.danmakuFontSize
        danmakuTop = SettingsRepository.shared.danmakuTop
        danmakuScroll = SettingsRepository.shared.danmakuScroll
        danmakuBottom = SettingsRepository.shared.danmakuBottom
        privateMode = SettingsRepository.shared.privateMode
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

private struct TVServerURLTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let focusRequestID: Int
    @Binding var wantsTextInput: Bool
    @Binding var isEditing: Bool
    let isActive: Bool
    let onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.backgroundColor = .clear
        textField.borderStyle = .none
        textField.textColor = UIColor(Color.kzText)
        textField.tintColor = UIColor(Color.kzPrimary)
        textField.font = UIFont.preferredFont(forTextStyle: .headline)
        textField.returnKeyType = .done
        textField.keyboardType = .URL
        textField.keyboardAppearance = .dark
        textField.clearButtonMode = .whileEditing
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.delegate = context.coordinator
        textField.attributedPlaceholder = placeholderText(isActive: false)
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange(_:)),
            for: .editingChanged
        )

        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }

        uiView.textColor = UIColor(isActive ? Color.kzOnPrimaryContainer : Color.kzText)
        uiView.tintColor = UIColor(Color.kzPrimary)
        uiView.backgroundColor = .clear
        uiView.attributedPlaceholder = placeholderText(isActive: isActive)

        context.coordinator.wantsTextInput = $wantsTextInput
        context.coordinator.isEditing = $isEditing

        if focusRequestID != context.coordinator.lastFocusRequestID,
           uiView.window != nil {
            context.coordinator.lastFocusRequestID = focusRequestID
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        } else if !wantsTextInput, uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.resignFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, wantsTextInput: $wantsTextInput, isEditing: $isEditing, onSubmit: onSubmit)
    }

    private func placeholderText(isActive: Bool) -> NSAttributedString {
        NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: UIColor(isActive ? Color.kzOnPrimaryContainer.opacity(0.52) : Color.kzTextSecondary.opacity(0.62)),
                .font: UIFont.preferredFont(forTextStyle: .headline)
            ]
        )
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String
        var wantsTextInput: Binding<Bool>
        var isEditing: Binding<Bool>
        var lastFocusRequestID = 0
        private let onSubmit: () -> Void

        init(
            text: Binding<String>,
            wantsTextInput: Binding<Bool>,
            isEditing: Binding<Bool>,
            onSubmit: @escaping () -> Void
        ) {
            _text = text
            self.wantsTextInput = wantsTextInput
            self.isEditing = isEditing
            self.onSubmit = onSubmit
        }

        @objc func textDidChange(_ textField: UITextField) {
            text = textField.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            onSubmit()
            wantsTextInput.wrappedValue = false
            textField.resignFirstResponder()
            return true
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            isEditing.wrappedValue = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            wantsTextInput.wrappedValue = false
            isEditing.wrappedValue = false
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
