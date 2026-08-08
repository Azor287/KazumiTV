//
//  PluginRulesView.swift
//  KazumiTV
//
//  Kazumi-style rule management adapted for tvOS.
//

import SwiftUI

struct PluginRulesView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var rules: [PluginRule] = []
    @State private var repositoryItems: [PluginRepositoryItem] = []
    @State private var isLoadingRules = false
    @State private var isUpdatingAll = false
    @State private var isInstallingRecommended = false
    @State private var isLoadingRepository = false
    @State private var repositorySortByName = false
    @State private var noticeText: String?
    @State private var editorContext: RuleEditorContext?
    @State private var showRepository = false
    @State private var showImport = false
    @State private var importText = ""
    @State private var shareText: String?
    @State private var deletingRule: PluginRule?
    @State private var testKeyword = "夏目友人帐"
    @State private var testingRuleName: String?
    @State private var testResult: PluginTestResult?

    private let pluginManager = PluginManager.shared

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    toolbar
                    testKeywordBar
                    rulesList
                }
                .padding(.horizontal, 72)
                .padding(.top, 26)
                .padding(.bottom, 72)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.kzBackground.ignoresSafeArea())

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
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadRules()
        }
        .onExitCommand {
            dismiss()
        }
        .sheet(item: $editorContext) { context in
            PluginRuleEditorView(rule: context.rule) { rule in
                Task {
                    await saveRule(rule)
                    editorContext = nil
                }
            }
        }
        .sheet(isPresented: $showRepository) {
            repositorySheet
        }
        .sheet(isPresented: $showImport) {
            importSheet
        }
        .alert("删除规则", isPresented: Binding(
            get: { deletingRule != nil },
            set: { if !$0 { deletingRule = nil } }
        )) {
            Button("取消", role: .cancel) {
                deletingRule = nil
            }
            Button("删除", role: .destructive) {
                if let deletingRule {
                    Task { await deleteRule(deletingRule) }
                }
            }
        } message: {
            Text("确定删除 \(deletingRule?.name ?? "") 吗？")
        }
        .alert("规则测试", isPresented: Binding(
            get: { testResult != nil },
            set: { if !$0 { testResult = nil } }
        )) {
            Button("好", role: .cancel) {
                testResult = nil
            }
        } message: {
            Text(testResult?.message ?? "")
        }
        .alert("规则分享", isPresented: Binding(
            get: { shareText != nil },
            set: { if !$0 { shareText = nil } }
        )) {
            Button("关闭", role: .cancel) {
                shareText = nil
            }
        } message: {
            Text(shareText ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("规则管理")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(.kzText)

            Text("管理番剧资源规则，支持更新、编辑、测试、分享、删除、排序和添加")
                .font(.headline)
                .foregroundColor(.kzTextSecondary)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            toolbarButton(title: isUpdatingAll ? "更新中" : "更新全部", icon: "arrow.triangle.2.circlepath", isBusy: isUpdatingAll) {
                Task { await updateAllRules() }
            }
            toolbarButton(title: "规则仓库", icon: "tray.and.arrow.down") {
                showRepository = true
                Task { await loadRepositoryIfNeeded() }
            }
            toolbarButton(title: isInstallingRecommended ? "安装中" : "安装推荐", icon: "star", isBusy: isInstallingRecommended) {
                Task { await installRecommendedRules() }
            }
            toolbarButton(title: "新建", icon: "plus") {
                editorContext = RuleEditorContext(rule: .template())
            }
            toolbarButton(title: "导入", icon: "doc.on.clipboard") {
                importText = ""
                showImport = true
            }
            toolbarButton(title: "恢复推荐", icon: "arrow.counterclockwise") {
                Task { await resetBundledRules() }
            }
        }
        .focusSection()
    }

    private var testKeywordBar: some View {
        HStack(spacing: 16) {
            Label("测试关键词", systemImage: "text.magnifyingglass")
                .font(.headline)
                .foregroundColor(.kzText)

            TextField("输入用于测试规则的番剧名", text: $testKeyword)
                .textFieldStyle(.plain)
                .font(.headline)
                .foregroundColor(.kzText)
                .padding(.horizontal, 18)
                .frame(height: 54)
                .background(Color.kzSurfaceContainerLow, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(18)
        .background(Color.kzSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var rulesList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("已安装规则")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.kzText)

                Text("\(rules.count)")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.kzOnPrimaryContainer)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.kzPrimaryContainer, in: Capsule())

                Spacer()

                if isLoadingRules {
                    ProgressView()
                        .tint(.kzPrimary)
                }
            }

            if rules.isEmpty {
                Text("暂无规则，可以从规则仓库导入或新建规则。")
                    .font(.headline)
                    .foregroundColor(.kzTextSecondary)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.kzSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(Array(rules.enumerated()), id: \.element.name) { index, rule in
                        PluginRuleRow(
                            rule: rule,
                            index: index,
                            count: rules.count,
                            isTesting: testingRuleName == rule.name,
                            update: { Task { await updateRule(rule) } },
                            edit: { editorContext = RuleEditorContext(rule: rule) },
                            test: { Task { await testRule(rule) } },
                            share: { shareRule(rule) },
                            delete: { deletingRule = rule },
                            moveUp: { Task { await moveRule(rule, direction: .up) } },
                            moveDown: { Task { await moveRule(rule, direction: .down) } }
                        )
                    }
                }
            }
        }
    }

    private var repositorySheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Text("规则仓库")
                        .font(.largeTitle.weight(.bold))
                        .foregroundColor(.kzText)

                    Spacer()

                    toolbarButton(title: repositorySortByName ? "按名称" : "按时间", icon: repositorySortByName ? "textformat" : "clock") {
                        repositorySortByName.toggle()
                    }

                    toolbarButton(title: isLoadingRepository ? "刷新中" : "刷新", icon: "arrow.clockwise", isBusy: isLoadingRepository) {
                        Task { await loadRepository(force: true) }
                    }
                }

                if repositoryItems.isEmpty && isLoadingRepository {
                    ProgressView()
                        .tint(.kzPrimary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if repositoryItems.isEmpty {
                    Text("暂无仓库数据，检查网络后刷新。")
                        .font(.headline)
                        .foregroundColor(.kzTextSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(sortedRepositoryItems) { item in
                                RepositoryRuleRow(
                                    item: item,
                                    status: repositoryStatus(for: item),
                                    install: { Task { await installRepositoryItem(item) } }
                                )
                            }
                        }
                        .padding(.bottom, 20)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .padding(36)
            .background(Color.kzBackground.ignoresSafeArea())
        }
    }

    private var importSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("导入规则")
                .font(.largeTitle.weight(.bold))
                .foregroundColor(.kzText)

            Text("粘贴 Kazumi 分享链接，格式为 kazumi://...")
                .font(.headline)
                .foregroundColor(.kzTextSecondary)

            TextField("kazumi://", text: $importText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.headline)
                .foregroundColor(.kzText)
                .lineLimit(4...8)
                .padding(18)
                .background(Color.kzSurfaceContainerLow, in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 14) {
                toolbarButton(title: "取消", icon: "xmark") {
                    showImport = false
                }
                toolbarButton(title: "导入", icon: "square.and.arrow.down") {
                    Task { await importRule() }
                }
            }

            Spacer()
        }
        .padding(36)
        .background(Color.kzBackground.ignoresSafeArea())
    }

    private var sortedRepositoryItems: [PluginRepositoryItem] {
        if repositorySortByName {
            return repositoryItems.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return repositoryItems.sorted { $0.lastUpdate > $1.lastUpdate }
    }

    private func toolbarButton(title: String, icon: String, isBusy: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .tint(.kzOnPrimaryContainer)
                } else {
                    Image(systemName: icon)
                        .font(.headline)
                }
                Text(title)
                    .font(.headline.weight(.semibold))
            }
            .foregroundColor(.kzText)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(Color.kzSurfaceContainerLow, in: Capsule())
        }
        .buttonStyle(TVPillButtonStyle())
        .disabled(isBusy)
    }

    @MainActor
    private func loadRules() async {
        isLoadingRules = true
        defer { isLoadingRules = false }

        do {
            try await pluginManager.loadPlugins()
            rules = await pluginManager.getAllPlugins()
        } catch {
            showNotice("规则加载失败")
        }
    }

    @MainActor
    private func saveRule(_ rule: PluginRule) async {
        do {
            try await pluginManager.upsertPlugin(rule)
            rules = await pluginManager.getAllPlugins()
            showNotice("规则已保存")
        } catch {
            showNotice("保存失败")
        }
    }

    @MainActor
    private func deleteRule(_ rule: PluginRule) async {
        do {
            try await pluginManager.deletePlugin(name: rule.name)
            rules = await pluginManager.getAllPlugins()
            deletingRule = nil
            showNotice("规则已删除")
        } catch {
            showNotice("删除失败")
        }
    }

    @MainActor
    private func moveRule(_ rule: PluginRule, direction: PluginMoveDirection) async {
        do {
            try await pluginManager.movePlugin(name: rule.name, direction: direction)
            rules = await pluginManager.getAllPlugins()
        } catch {
            showNotice("排序失败")
        }
    }

    @MainActor
    private func updateRule(_ rule: PluginRule) async {
        do {
            let updated = try await pluginManager.installRepositoryPlugin(name: rule.name)
            rules = await pluginManager.getAllPlugins()
            showNotice("\(updated.name) 已更新")
        } catch {
            print("PluginRulesView: 更新规则失败 \(rule.name): \(error.localizedDescription)")
            showNotice("更新失败: \(shortError(error))")
        }
    }

    @MainActor
    private func updateAllRules() async {
        isUpdatingAll = true
        defer { isUpdatingAll = false }

        do {
            let count = try await pluginManager.updateInstalledPluginsFromRepository()
            rules = await pluginManager.getAllPlugins()
            showNotice(count == 0 ? "所有规则已是最新" : "更新成功 \(count) 条")
        } catch {
            print("PluginRulesView: 更新全部规则失败: \(error.localizedDescription)")
            showNotice("更新失败: \(shortError(error))")
        }
    }

    @MainActor
    private func installRecommendedRules() async {
        isInstallingRecommended = true
        defer { isInstallingRecommended = false }

        do {
            let count = try await pluginManager.installRecommendedRepositoryPlugins()
            rules = await pluginManager.getAllPlugins()
            showNotice(count == 0 ? "推荐规则已安装" : "已安装推荐规则 \(count) 条")
        } catch {
            print("PluginRulesView: 安装推荐规则失败: \(error.localizedDescription)")
            showNotice("安装失败: \(shortError(error))")
        }
    }

    @MainActor
    private func resetBundledRules() async {
        do {
            try await pluginManager.resetToBundledPlugins()
            rules = await pluginManager.getAllPlugins()
            showNotice("已恢复推荐规则")
        } catch {
            showNotice("恢复失败")
        }
    }

    @MainActor
    private func importRule() async {
        do {
            let plugin = try await pluginManager.importSharedPlugin(importText)
            rules = await pluginManager.getAllPlugins()
            showImport = false
            showNotice("已导入 \(plugin.name)")
        } catch {
            showNotice("导入失败")
        }
    }

    @MainActor
    private func testRule(_ rule: PluginRule) async {
        testingRuleName = rule.name
        defer { testingRuleName = nil }

        let keyword = testKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "夏目友人帐" : testKeyword
        testResult = await pluginManager.testPlugin(rule, keyword: keyword)
    }

    @MainActor
    private func shareRule(_ rule: PluginRule) {
        shareText = rule.shareURL
    }

    @MainActor
    private func loadRepositoryIfNeeded() async {
        guard repositoryItems.isEmpty else { return }
        await loadRepository(force: false)
    }

    @MainActor
    private func loadRepository(force: Bool) async {
        if isLoadingRepository { return }
        isLoadingRepository = true
        defer { isLoadingRepository = false }

        do {
            repositoryItems = try await pluginManager.fetchRepositoryIndex()
        } catch {
            print("PluginRulesView: 加载规则仓库失败: \(error.localizedDescription)")
            showNotice("规则仓库加载失败: \(shortError(error))")
        }
    }

    @MainActor
    private func installRepositoryItem(_ item: PluginRepositoryItem) async {
        do {
            let plugin = try await pluginManager.installRepositoryPlugin(name: item.name)
            rules = await pluginManager.getAllPlugins()
            showNotice("\(plugin.name) 已安装")
        } catch {
            print("PluginRulesView: 安装规则失败 \(item.name): \(error.localizedDescription)")
            showNotice("安装失败: \(shortError(error))")
        }
    }

    private func repositoryStatus(for item: PluginRepositoryItem) -> PluginRepositoryStatus {
        guard let rule = rules.first(where: { $0.name == item.name }) else {
            return .notInstalled
        }
        return rule.version == item.version ? .installed : .updatable
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

    private func shortError(_ error: Error) -> String {
        let message = error.localizedDescription
        if message.count <= 28 {
            return message
        }
        return String(message.prefix(28)) + "..."
    }
}

private struct PluginRuleRow: View {
    let rule: PluginRule
    let index: Int
    let count: Int
    let isTesting: Bool
    let update: () -> Void
    let edit: () -> Void
    let test: () -> Void
    let share: () -> Void
    let delete: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text(rule.name.isEmpty ? "未命名规则" : rule.name)
                            .font(.title3.weight(.bold))
                            .foregroundColor(.kzText)

                        tag("v\(rule.version)")
                        tag(rule.useWebview ? "webview" : "direct")
                        if rule.adBlocker == true {
                            tag("adblock")
                        }
                    }

                    Text(rule.baseURL)
                        .font(.subheadline)
                        .foregroundColor(.kzTextSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 20)

                HStack(spacing: 8) {
                    iconButton("arrow.up", disabled: index == 0, action: moveUp)
                    iconButton("arrow.down", disabled: index == count - 1, action: moveDown)
                }
            }

            HStack(spacing: 10) {
                actionButton("更新", "arrow.triangle.2.circlepath", update)
                actionButton("编辑", "pencil", edit)
                actionButton(isTesting ? "测试中" : "测试", "stethoscope", test, isBusy: isTesting)
                actionButton("分享", "square.and.arrow.up", share)
                actionButton("删除", "trash", delete, isDestructive: true)
            }
        }
        .padding(18)
        .background(Color.kzSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func tag(_ value: String) -> some View {
        Text(value)
            .font(.caption.weight(.bold))
            .foregroundColor(.kzOnPrimaryContainer)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.kzPrimaryContainer.opacity(0.78), in: Capsule())
    }

    private func actionButton(_ title: String, _ icon: String, _ action: @escaping () -> Void, isBusy: Bool = false, isDestructive: Bool = false) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isBusy {
                    ProgressView()
                        .tint(.kzText)
                } else {
                    Image(systemName: icon)
                }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(isDestructive ? .red : .kzText)
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(Color.kzSurfaceContainerLow, in: Capsule())
        }
        .buttonStyle(TVPillButtonStyle())
        .disabled(isBusy)
    }

    private func iconButton(_ icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.headline.weight(.bold))
                .foregroundColor(disabled ? .kzTextSecondary.opacity(0.45) : .kzText)
                .frame(width: 44, height: 38)
        }
        .buttonStyle(TVIconButtonStyle())
        .disabled(disabled)
    }
}

private struct RepositoryRuleRow: View {
    let item: PluginRepositoryItem
    let status: PluginRepositoryStatus
    let install: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(item.name)
                        .font(.headline.weight(.bold))
                        .foregroundColor(.kzText)

                    Text(item.version)
                        .font(.caption.weight(.bold))
                        .foregroundColor(.kzOnPrimaryContainer)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.kzPrimaryContainer.opacity(0.78), in: Capsule())

                    if item.antiCrawlerEnabled {
                        Text("captcha")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.kzText)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.kzSurfaceContainer, in: Capsule())
                    }
                }

                Text(item.author.isEmpty ? "未知作者" : item.author)
                    .font(.subheadline)
                    .foregroundColor(.kzTextSecondary)
            }

            Spacer()

            Button(action: install) {
                Text(status.actionTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(status == .installed ? .kzTextSecondary : .kzText)
                    .frame(width: 96, height: 44)
                    .background(Color.kzSurfaceContainerLow, in: Capsule())
            }
            .buttonStyle(TVPillButtonStyle())
            .disabled(status == .installed)
        }
        .padding(16)
        .background(Color.kzSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct PluginRuleEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let rule: PluginRule
    let onSave: (PluginRule) -> Void

    @State private var name: String
    @State private var version: String
    @State private var baseURL: String
    @State private var searchURL: String
    @State private var searchList: String
    @State private var searchName: String
    @State private var searchResult: String
    @State private var chapterRoads: String
    @State private var chapterResult: String
    @State private var userAgent: String
    @State private var referer: String
    @State private var usePost: Bool
    @State private var useLegacyParser: Bool
    @State private var useWebview: Bool
    @State private var useNativePlayer: Bool
    @State private var adBlocker: Bool

    init(rule: PluginRule, onSave: @escaping (PluginRule) -> Void) {
        self.rule = rule
        self.onSave = onSave
        _name = State(initialValue: rule.name)
        _version = State(initialValue: rule.version)
        _baseURL = State(initialValue: rule.baseURL)
        _searchURL = State(initialValue: rule.searchURL)
        _searchList = State(initialValue: rule.searchList)
        _searchName = State(initialValue: rule.searchName)
        _searchResult = State(initialValue: rule.searchResult)
        _chapterRoads = State(initialValue: rule.chapterRoads)
        _chapterResult = State(initialValue: rule.chapterResult)
        _userAgent = State(initialValue: rule.userAgent)
        _referer = State(initialValue: rule.referer ?? "")
        _usePost = State(initialValue: rule.usePost ?? false)
        _useLegacyParser = State(initialValue: rule.useLegacyParser ?? false)
        _useWebview = State(initialValue: rule.useWebview)
        _useNativePlayer = State(initialValue: rule.useNativePlayer)
        _adBlocker = State(initialValue: rule.adBlocker ?? false)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("规则编辑器")
                        .font(.largeTitle.weight(.bold))
                        .foregroundColor(.kzText)

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundColor(.kzText)
                            .frame(width: 54, height: 54)
                    }
                    .buttonStyle(TVIconButtonStyle())
                }

                editorField("Name", text: $name)
                editorField("Version", text: $version)
                editorField("BaseURL", text: $baseURL)
                editorField("SearchURL", text: $searchURL)
                editorField("SearchList", text: $searchList, lines: 2...4)
                editorField("SearchName", text: $searchName, lines: 2...4)
                editorField("SearchResult", text: $searchResult, lines: 2...4)
                editorField("ChapterRoads", text: $chapterRoads, lines: 2...4)
                editorField("ChapterResult", text: $chapterResult, lines: 2...4)
                editorField("UserAgent", text: $userAgent, lines: 2...3)
                editorField("Referer", text: $referer)

                VStack(alignment: .leading, spacing: 10) {
                    Text("行为")
                        .font(.headline)
                        .foregroundColor(.kzText)

                    Toggle("WebView 解析", isOn: $useWebview)
                    Toggle("内置播放器", isOn: $useNativePlayer)
                    Toggle("POST 搜索", isOn: $usePost)
                    Toggle("简易解析", isOn: $useLegacyParser)
                    Toggle("广告过滤", isOn: $adBlocker)
                }
                .foregroundColor(.kzText)
                .padding(18)
                .background(Color.kzSurface, in: RoundedRectangle(cornerRadius: 14))

                HStack(spacing: 14) {
                    Button {
                        dismiss()
                    } label: {
                        Label("取消", systemImage: "xmark")
                            .font(.headline)
                            .foregroundColor(.kzText)
                            .frame(width: 128, height: 52)
                            .background(Color.kzSurfaceContainerLow, in: Capsule())
                    }
                    .buttonStyle(TVPillButtonStyle())

                    Button {
                        onSave(buildRule())
                    } label: {
                        Label("保存", systemImage: "checkmark")
                            .font(.headline.weight(.bold))
                            .foregroundColor(.kzOnPrimaryContainer)
                            .frame(width: 128, height: 52)
                            .background(Color.kzPrimaryContainer, in: Capsule())
                    }
                    .buttonStyle(TVPillButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(36)
        }
        .background(Color.kzBackground.ignoresSafeArea())
    }

    private func editorField(_ title: String, text: Binding<String>, lines: ClosedRange<Int> = 1...2) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.kzText)

            TextField(title, text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.headline)
                .foregroundColor(.kzText)
                .lineLimit(lines)
                .padding(16)
                .background(Color.kzSurfaceContainerLow, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func buildRule() -> PluginRule {
        PluginRule(
            api: rule.api,
            type: rule.type,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            version: version.trimmingCharacters(in: .whitespacesAndNewlines),
            muliSources: rule.muliSources,
            useWebview: useWebview,
            useNativePlayer: useNativePlayer,
            usePost: usePost,
            useLegacyParser: useLegacyParser,
            userAgent: userAgent,
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            searchURL: searchURL.trimmingCharacters(in: .whitespacesAndNewlines),
            searchList: searchList.trimmingCharacters(in: .whitespacesAndNewlines),
            searchName: searchName.trimmingCharacters(in: .whitespacesAndNewlines),
            searchResult: searchResult.trimmingCharacters(in: .whitespacesAndNewlines),
            chapterRoads: chapterRoads.trimmingCharacters(in: .whitespacesAndNewlines),
            chapterResult: chapterResult.trimmingCharacters(in: .whitespacesAndNewlines),
            referer: referer.trimmingCharacters(in: .whitespacesAndNewlines),
            adBlocker: adBlocker,
            antiCrawlerConfig: rule.antiCrawlerConfig,
            sourceSearch: rule.sourceSearch,
            capability: rule.capability,
            fallback: rule.fallback,
            observability: rule.observability,
            searchMode: rule.searchMode,
            chapterMode: rule.chapterMode,
            searchApiConfig: rule.searchApiConfig,
            chapterApiConfig: rule.chapterApiConfig,
            nativeResolver: rule.nativeResolver,
            mediaPatterns: rule.mediaPatterns,
            iframePatterns: rule.iframePatterns,
            playbackHeaders: rule.playbackHeaders
        )
    }
}

private struct RuleEditorContext: Identifiable {
    let id = UUID()
    let rule: PluginRule
}

#Preview {
    PluginRulesView()
        .preferredColorScheme(.dark)
}
