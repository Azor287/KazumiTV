//
//  PluginManager.swift
//  KazumiTV
//
//  Plugin Manager - loads and manages scraping plugins
//

import Foundation
import Fuzi

private struct PluginSearchTimeoutError: LocalizedError {
    let pluginName: String

    var errorDescription: String? {
        "\(pluginName) 搜索超时"
    }
}

actor PluginManager {
    static let shared = PluginManager()

    private let repositoryBaseURLs = [
        "https://raw.githubusercontent.com/Predidit/KazumiRules/main/",
        "https://cdn.jsdelivr.net/gh/Predidit/KazumiRules@main/",
    ]
    private let recommendedRepositoryPluginNames = [
        "MXdm",
        "omofun03",
        "baimao",
        "enlie",
        "gpjda",
        "aafun",
        "mwcy",
        "gugu3",
        "7sefun",
        "yishijie",
        "DM84",
        "AGE",
        "xfdmneo",
    ]
    private let recommendedBootstrapFlagKey = "kazumi.pluginRepositoryRecommendedBootstrapped.v1"
    private let maxSupportedAPILevel = 6
    private let pluginsFileName = "plugins.json"
    private let repositoryHeaders = [
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15",
        "Accept": "application/json,text/plain,*/*",
    ]

    private var plugins: [PluginRule] = []
    private var pluginsByName: [String: PluginRule] = [:]
    private var searchWarmupHosts = Set<String>()
    private let searchTimeoutNanoseconds: UInt64 = 12_000_000_000

    private init() {}

    // MARK: - Load Plugins

    /// Load all plugins from persistent storage, seeding bundled JSON files on first run.
    func loadPlugins() async throws {
        plugins = []
        pluginsByName = [:]

        let persistedRules = try loadPersistedPlugins()
        if !persistedRules.isEmpty {
            setPlugins(persistedRules)
            return
        }

        let defaultRules = try await loadDefaultPlugins()
        try savePlugins(defaultRules)
        setPlugins(defaultRules)

        if plugins.isEmpty {
            throw PluginError.failedToLoadPlugins
        }
    }

    func reloadPlugins() async throws {
        try await loadPlugins()
    }

    /// Load a single plugin from JSON file
    private func loadPlugin(from url: URL) throws -> PluginRule {
        let data = try Data(contentsOf: url)
        let plugin = try JSONDecoder().decode(PluginRule.self, from: data)
        return plugin
    }

    private func loadBundledPlugins() throws -> [PluginRule] {
        let pluginURLs = bundledPluginURLs()
        guard !pluginURLs.isEmpty else {
            throw PluginError.pluginsDirectoryNotFound
        }

        return pluginURLs.compactMap { try? loadPlugin(from: $0) }
    }

    private func loadDefaultPlugins() async throws -> [PluginRule] {
        let bundledRules = try loadBundledPlugins()
        let recommendedRules = (try? await fetchRecommendedRepositoryPlugins(excluding: [])) ?? []
        if !recommendedRules.isEmpty {
            UserDefaults.standard.set(true, forKey: recommendedBootstrapFlagKey)
            return mergePlugins(preferred: recommendedRules, fallback: bundledRules)
        }
        return bundledRules
    }

    private func fetchRecommendedRepositoryPlugins(excluding installedNames: Set<String>) async throws -> [PluginRule] {
        let repositoryItems = try await fetchRepositoryIndex()
        let recommendedAvailableNames = Set(
            repositoryItems
                .filter { $0.useNativePlayer && !$0.antiCrawlerEnabled }
                .map(\.name)
        )

        var rules: [PluginRule] = []
        for name in recommendedRepositoryPluginNames where !installedNames.contains(name) && recommendedAvailableNames.contains(name) {
            do {
                let plugin = try await fetchRepositoryPlugin(name: name)
                guard plugin.useNativePlayer else { continue }
                rules.append(plugin)
            } catch {
                print("PluginManager: 推荐规则 \(name) 下载失败: \(error.localizedDescription)")
            }
        }
        return rules
    }

    private func mergePlugins(preferred: [PluginRule], fallback: [PluginRule]) -> [PluginRule] {
        var seen = Set<String>()
        var merged: [PluginRule] = []

        for plugin in preferred + fallback {
            guard !seen.contains(plugin.name) else { continue }
            seen.insert(plugin.name)
            merged.append(plugin)
        }

        return merged
    }

    private func loadPersistedPlugins() throws -> [PluginRule] {
        for fileURL in persistedPluginsFileURLs() where FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([PluginRule].self, from: data)
        }
        return []
    }

    private func savePlugins(_ rules: [PluginRule]? = nil) throws {
        let data = try JSONEncoder.prettyPluginEncoder.encode(rules ?? plugins)
        var failures: [String] = []

        for fileURL in persistedPluginsFileURLs() {
            do {
                let directoryURL = fileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                try data.write(to: fileURL, options: .atomic)
                return
            } catch {
                failures.append("\(fileURL.path): \(error.localizedDescription)")
            }
        }

        throw PluginError.storageUnavailable(failures.joined(separator: "; "))
    }

    private func persistedPluginsFileURLs() -> [URL] {
        let fileManager = FileManager.default
        var urls: [URL] = []

        if let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            urls.append(
                applicationSupportURL
                    .appendingPathComponent("Plugins", isDirectory: true)
                    .appendingPathComponent(pluginsFileName)
            )
            urls.append(
                applicationSupportURL
                    .appendingPathComponent("KazumiTV", isDirectory: true)
                    .appendingPathComponent("Plugins", isDirectory: true)
                    .appendingPathComponent(pluginsFileName)
            )
        }

        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            urls.append(
                documentsURL
                    .appendingPathComponent("KazumiTV", isDirectory: true)
                    .appendingPathComponent("Plugins", isDirectory: true)
                    .appendingPathComponent(pluginsFileName)
            )
        }

        if let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            urls.append(
                cachesURL
                    .appendingPathComponent("KazumiTV", isDirectory: true)
                    .appendingPathComponent("Plugins", isDirectory: true)
                    .appendingPathComponent(pluginsFileName)
            )
        }

        return urls
    }

    private func setPlugins(_ rules: [PluginRule]) {
        let normalizedRules = rules.map(normalizedPlugin)
        plugins = normalizedRules
        pluginsByName = [:]
        for rule in normalizedRules {
            pluginsByName[rule.name] = rule
        }
    }

    private func normalizedPlugin(_ plugin: PluginRule) -> PluginRule {
        guard plugin.name == "gugu3" else { return plugin }

        return PluginRule(
            api: plugin.api,
            type: plugin.type,
            name: plugin.name,
            version: plugin.version,
            muliSources: plugin.muliSources,
            useWebview: plugin.useWebview,
            useNativePlayer: plugin.useNativePlayer,
            usePost: plugin.usePost,
            useLegacyParser: plugin.useLegacyParser,
            userAgent: plugin.userAgent,
            baseURL: plugin.baseURL,
            searchURL: plugin.searchURL,
            searchList: "//div[contains(concat(' ', normalize-space(@class), ' '), ' public-list-box ') and contains(concat(' ', normalize-space(@class), ' '), ' search-box ')]",
            searchName: ".//div[contains(concat(' ', normalize-space(@class), ' '), ' thumb-txt ')]",
            searchResult: ".//a[contains(concat(' ', normalize-space(@class), ' '), ' public-list-exp ')]",
            chapterRoads: plugin.chapterRoads,
            chapterResult: plugin.chapterResult,
            referer: plugin.referer,
            adBlocker: plugin.adBlocker,
            antiCrawlerConfig: plugin.antiCrawlerConfig,
            sourceSearch: plugin.sourceSearch,
            capability: plugin.capability,
            fallback: plugin.fallback,
            observability: plugin.observability,
            nativeResolver: plugin.nativeResolver,
            mediaPatterns: plugin.mediaPatterns,
            iframePatterns: plugin.iframePatterns,
            playbackHeaders: plugin.playbackHeaders
        )
    }

    private func bundledPluginURLs() -> [URL] {
        var urls: [URL] = []

        if let nestedURLs = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Plugins") {
            urls.append(contentsOf: nestedURLs)
        }

        if urls.isEmpty, let flatURLs = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) {
            urls.append(contentsOf: flatURLs.filter { url in
                ["AGE", "DM84", "aafun"].contains(url.deletingPathExtension().lastPathComponent)
            })
        }

        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - Access Plugins

    /// Get all loaded plugins
    func getAllPlugins() -> [PluginRule] {
        return plugins
    }

    /// Get plugin by name
    func getPlugin(name: String) -> PluginRule? {
        return pluginsByName[name]
    }

    /// Get plugins supporting webview video extraction
    func getWebviewPlugins() -> [PluginRule] {
        return plugins.filter { $0.useWebview }
    }

    // MARK: - Manage Plugins

    func upsertPlugin(_ plugin: PluginRule) async throws {
        if let index = plugins.firstIndex(where: { $0.name == plugin.name }) {
            plugins[index] = plugin
        } else {
            plugins.append(plugin)
        }
        setPlugins(plugins)
        try savePlugins()
    }

    func deletePlugin(name: String) async throws {
        plugins.removeAll { $0.name == name }
        setPlugins(plugins)
        try savePlugins()
    }

    func movePlugin(name: String, direction: PluginMoveDirection) async throws {
        guard let index = plugins.firstIndex(where: { $0.name == name }) else { return }
        let targetIndex: Int
        switch direction {
        case .up:
            targetIndex = max(0, index - 1)
        case .down:
            targetIndex = min(plugins.count - 1, index + 1)
        }
        guard targetIndex != index else { return }
        let item = plugins.remove(at: index)
        plugins.insert(item, at: targetIndex)
        setPlugins(plugins)
        try savePlugins()
    }

    func resetToBundledPlugins() async throws {
        UserDefaults.standard.removeObject(forKey: recommendedBootstrapFlagKey)
        let defaultRules = try await loadDefaultPlugins()
        try savePlugins(defaultRules)
        setPlugins(defaultRules)
    }

    func importSharedPlugin(_ value: String) async throws -> PluginRule {
        let plugin = try PluginRule.decodeShareURL(value.trimmingCharacters(in: .whitespacesAndNewlines))
        try await upsertPlugin(plugin)
        return plugin
    }

    // MARK: - Rule Repository

    func fetchRepositoryIndex() async throws -> [PluginRepositoryItem] {
        let data = try await downloadRepositoryFile(fileName: "index.json")
        return try JSONDecoder().decode([PluginRepositoryItem].self, from: data)
    }

    func fetchRepositoryPlugin(name: String) async throws -> PluginRule {
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let data = try await downloadRepositoryFile(fileName: encodedName + ".json")
        let plugin = try JSONDecoder().decode(PluginRule.self, from: data)
        guard Int(plugin.api) ?? 0 <= maxSupportedAPILevel else {
            throw PluginError.incompatibleAPI(plugin.api)
        }
        return plugin
    }

    private func downloadRepositoryFile(fileName: String) async throws -> Data {
        var failureMessages: [String] = []

        for baseURL in repositoryBaseURLs {
            let urlString = baseURL + fileName
            guard let url = URL(string: urlString) else {
                failureMessages.append("Invalid URL: \(urlString)")
                continue
            }

            do {
                return try await APIClient.shared.download(url: url, headers: repositoryHeaders)
            } catch {
                let message = error.localizedDescription
                failureMessages.append("\(url.host ?? baseURL): \(message)")
                print("PluginManager: 规则仓库直连失败 \(urlString): \(message)")
            }
        }

        throw PluginError.repositoryDownloadFailed(fileName, failureMessages.joined(separator: "; "))
    }

    func installRepositoryPlugin(name: String) async throws -> PluginRule {
        let plugin = try await fetchRepositoryPlugin(name: name)
        try await upsertPlugin(plugin)
        return plugin
    }

    func installRecommendedRepositoryPlugins() async throws -> Int {
        let installedNames = Set(plugins.map(\.name))
        let recommendedRules = try await fetchRecommendedRepositoryPlugins(excluding: installedNames)
        guard !recommendedRules.isEmpty else {
            UserDefaults.standard.set(true, forKey: recommendedBootstrapFlagKey)
            return 0
        }

        var existingRulesByName: [String: PluginRule] = [:]
        for plugin in plugins {
            existingRulesByName[plugin.name] = plugin
        }
        var recommendedRulesByName: [String: PluginRule] = [:]
        for plugin in recommendedRules {
            recommendedRulesByName[plugin.name] = plugin
        }
        let orderedRecommendedRules = recommendedRepositoryPluginNames.compactMap { name in
            recommendedRulesByName[name] ?? existingRulesByName[name]
        }
        let nonRecommendedRules = plugins.filter { !recommendedRepositoryPluginNames.contains($0.name) }
        let merged = mergePlugins(preferred: orderedRecommendedRules, fallback: nonRecommendedRules)
        setPlugins(merged)
        try savePlugins()
        UserDefaults.standard.set(true, forKey: recommendedBootstrapFlagKey)
        return recommendedRules.count
    }

    func updateInstalledPluginsFromRepository() async throws -> Int {
        let index = try await fetchRepositoryIndex()
        var versionsByName: [String: String] = [:]
        for item in index {
            versionsByName[item.name] = item.version
        }
        var updatedCount = 0

        for plugin in plugins {
            guard let remoteVersion = versionsByName[plugin.name],
                  remoteVersion != plugin.version else {
                continue
            }

            _ = try await installRepositoryPlugin(name: plugin.name)
            updatedCount += 1
        }

        return updatedCount
    }

    func repositoryStatus(for item: PluginRepositoryItem) -> PluginRepositoryStatus {
        guard let plugin = pluginsByName[item.name] else {
            return .notInstalled
        }

        return plugin.version == item.version ? .installed : .updatable
    }

    func testPlugin(_ plugin: PluginRule, keyword: String) async -> PluginTestResult {
        do {
            let searchResults = try await searchWithPlugin(plugin: plugin, keyword: keyword)
            var roadCount = 0
            var episodeCount = 0

            if let first = searchResults.first {
                let roads = try await getChapters(pageURL: first.src, plugin: plugin)
                roadCount = roads.count
                episodeCount = roads.reduce(0) { $0 + $1.episodes.count }
            }

            return PluginTestResult(
                isSuccess: true,
                message: "搜索 \(searchResults.count) 个结果，线路 \(roadCount) 条，章节 \(episodeCount) 个"
            )
        } catch {
            return PluginTestResult(
                isSuccess: false,
                message: error.localizedDescription
            )
        }
    }

    // MARK: - Search

    /// Search using all available plugins
    func search(keyword: String) async throws -> [SearchItem] {
        let activePlugins = plugins.filter { $0.playbackCapability.searchSupported }
        let timeoutNanoseconds = searchTimeoutNanoseconds

        return await withTaskGroup(of: [SearchItem].self) { group in
            for plugin in activePlugins {
                group.addTask {
                    do {
                        return try await Self.searchWithPluginTimeout(
                            plugin: plugin,
                            keyword: keyword,
                            timeoutNanoseconds: timeoutNanoseconds
                        )
                    } catch {
                        print("Plugin \(plugin.name) search failed: \(error)")
                        return []
                    }
                }
            }

            var results: [SearchItem] = []
            for await pluginResults in group {
                results.append(contentsOf: pluginResults)
            }
            return results
        }
    }

    private static func searchWithPluginTimeout(
        plugin: PluginRule,
        keyword: String,
        timeoutNanoseconds: UInt64
    ) async throws -> [SearchItem] {
        try await withThrowingTaskGroup(of: [SearchItem].self) { group in
            group.addTask {
                try await PluginManager.shared.searchWithPlugin(plugin: plugin, keyword: keyword)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw PluginSearchTimeoutError(pluginName: plugin.name)
            }
            defer { group.cancelAll() }

            guard let results = try await group.next() else {
                throw CancellationError()
            }
            return results
        }
    }

    /// Search using a specific plugin
    func searchWithPlugin(plugin: PluginRule, keyword: String) async throws -> [SearchItem] {
        let searchURL = plugin.buildSearchURL(keyword: keyword)
        guard let url = URL(string: searchURL) else {
            throw PluginError.invalidURL(searchURL)
        }

        let headers = Self.searchHTTPHeaders(for: plugin, requestURL: url)
        await warmUpSearchSessionIfNeeded(plugin: plugin, requestURL: url, headers: headers)
        return try await Self.searchWithPluginRule(plugin: plugin, keyword: keyword, resolvedURL: url, headers: headers)
    }

    private func warmUpSearchSessionIfNeeded(plugin: PluginRule, requestURL: URL, headers: [String: String]) async {
        guard let warmupURL = Self.warmupURL(for: plugin, fallbackURL: requestURL),
              let warmupKey = Self.hostKey(for: warmupURL),
              !searchWarmupHosts.contains(warmupKey) else {
            return
        }

        searchWarmupHosts.insert(warmupKey)

        var warmupHeaders = headers
        warmupHeaders["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8"
        warmupHeaders["Referer"] = Self.defaultReferer(for: plugin)
        warmupHeaders["Sec-Fetch-Site"] = "none"

        do {
            _ = try await APIClient.shared.fetchHTML(url: warmupURL, headers: warmupHeaders, timeout: 6)
            print("PluginManager: \(plugin.name) 搜索预热成功 \(warmupURL.host ?? warmupURL.absoluteString)")
        } catch {
            print("PluginManager: \(plugin.name) 搜索预热失败: \(error.localizedDescription)")
        }
    }

    private static func searchWithPluginRule(
        plugin: PluginRule,
        keyword: String,
        resolvedURL: URL? = nil,
        headers resolvedHeaders: [String: String]? = nil
    ) async throws -> [SearchItem] {
        let api = APIClient.shared

        let searchURL = resolvedURL?.absoluteString ?? plugin.buildSearchURL(keyword: keyword)
        guard let url = resolvedURL ?? URL(string: searchURL) else {
            throw PluginError.invalidURL(searchURL)
        }

        var headers = resolvedHeaders ?? searchHTTPHeaders(for: plugin, requestURL: url)
        let html: String

        if plugin.usePost == true {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw PluginError.invalidURL(searchURL)
            }

            var form: [String: String] = [:]
            for item in components.queryItems ?? [] {
                form[item.name] = item.value ?? ""
            }
            components.queryItems = nil

            guard let postURL = components.url else {
                throw PluginError.invalidURL(searchURL)
            }

            if let origin = origin(for: postURL) {
                headers["Origin"] = origin
            }
            headers["Sec-Fetch-Site"] = secFetchSite(requestURL: postURL, plugin: plugin)
            html = try await api.postFormHTML(url: postURL, form: form, headers: headers)
        } else {
            html = try await api.fetchHTML(url: url, headers: headers)
        }

        return try parseSearchResults(html: html, plugin: plugin)
    }

    private static func parseSearchResults(html: String, plugin: PluginRule) throws -> [SearchItem] {
        guard let doc = try? HTMLDocument(string: html) else {
            throw PluginError.parsingFailed
        }

        var results: [SearchItem] = []

        let nodes = doc.xpath(plugin.searchList)

        for node in nodes {
            let nameElement = node.xpath(scopedSearchXPath(plugin.searchName)).first
            let name = nameElement?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let src = node.xpath(scopedSearchXPath(plugin.searchResult)).first?.attr("href") ?? ""

            guard !name.isEmpty && !src.isEmpty else { continue }

            let fullURL = buildSearchFullURL(base: plugin.baseURL, path: src)

            let item = SearchItem(
                name: name,
                nameCn: name,
                src: fullURL,
                pluginName: plugin.name
            )
            results.append(item)
        }

        return results
    }

    private static func scopedSearchXPath(_ xpath: String) -> String {
        let value = xpath.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("//") {
            return "." + value
        }
        if value.hasPrefix("/") {
            return "." + value
        }
        return value
    }

    private static func searchHTTPHeaders(for plugin: PluginRule, requestURL: URL? = nil) -> [String: String] {
        var headers: [String: String] = [
            "User-Agent": plugin.userAgent.isEmpty
                ? "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"
                : plugin.userAgent,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7",
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "DNT": "1",
            "Pragma": "no-cache",
            "Referer": defaultReferer(for: plugin),
            "Sec-Fetch-Dest": "document",
            "Sec-Fetch-Mode": "navigate",
            "Sec-Fetch-Site": secFetchSite(requestURL: requestURL, plugin: plugin),
            "Sec-Fetch-User": "?1",
            "Upgrade-Insecure-Requests": "1"
        ]

        if let referer = plugin.referer, !referer.isEmpty {
            headers["Referer"] = referer
        }

        return headers
    }

    private static func defaultReferer(for plugin: PluginRule) -> String {
        plugin.baseURL.hasSuffix("/") ? plugin.baseURL : plugin.baseURL + "/"
    }

    private static func warmupURL(for plugin: PluginRule, fallbackURL: URL) -> URL? {
        if let baseURL = URL(string: plugin.baseURL), baseURL.host != nil {
            return baseURL
        }

        var components = URLComponents(url: fallbackURL, resolvingAgainstBaseURL: false)
        components?.path = "/"
        components?.query = nil
        components?.fragment = nil
        return components?.url
    }

    private static func hostKey(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        return "\(url.scheme?.lowercased() ?? "https")://\(host)"
    }

    private static func origin(for url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        if let port = url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    private static func secFetchSite(requestURL: URL?, plugin: PluginRule) -> String {
        guard let requestURL,
              let requestHost = requestURL.host?.lowercased(),
              let baseHost = URL(string: plugin.baseURL)?.host?.lowercased() else {
            return "same-origin"
        }

        if requestHost == baseHost {
            return "same-origin"
        }

        let requestRoot = rootDomain(for: requestHost)
        let baseRoot = rootDomain(for: baseHost)
        return requestRoot == baseRoot ? "same-site" : "cross-site"
    }

    private static func rootDomain(for host: String) -> String {
        let parts = host.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return host }
        return parts.suffix(2).joined(separator: ".")
    }

    private static func buildSearchFullURL(base: String, path: String) -> String {
        if path.hasPrefix("http") {
            return path
        }

        if path.hasPrefix("//") {
            return "https:" + path
        }

        var baseURL = base
        if baseURL.hasSuffix("/") {
            baseURL = String(baseURL.dropLast())
        }

        if path.hasPrefix("/") {
            return baseURL + path
        }

        return baseURL + "/" + path
    }

    // MARK: - Chapter/Episode Parsing

    /// Get episode list from a bangumi page
    func getChapters(pageURL: String, plugin: PluginRule) async throws -> [ChapterRoad] {
        let api = APIClient.shared

        let chapterPageURL = normalizeChapterPageURL(pageURL, plugin: plugin)
        guard let url = URL(string: chapterPageURL) else {
            throw PluginError.invalidURL(chapterPageURL)
        }

        let headers = pluginHTTPHeaders(plugin: plugin)

        let html = try await api.fetchHTML(url: url, headers: headers)

        return try parseChapters(html: html, plugin: plugin)
    }

    private func parseChapters(html: String, plugin: PluginRule) throws -> [ChapterRoad] {
        guard let doc = try? HTMLDocument(string: html) else {
            throw PluginError.parsingFailed
        }

        var roads: [ChapterRoad] = []

        let roadNodes = doc.xpath(plugin.chapterRoads)

        for (roadIndex, roadNode) in roadNodes.enumerated() {
            let episodeNodes = roadNode.xpath(scopedXPath(plugin.chapterResult))

            var episodes: [ChapterRoad.EpisodeItem] = []
            var episodeNum = 1

            for epNode in episodeNodes {
                let name = epNode.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let src = extractLink(from: epNode)

                guard isValidPluginPath(src) else { continue }

                let fullURL = buildFullURL(base: plugin.baseURL, path: src)
                guard !isPluginRootURL(fullURL, plugin: plugin) else { continue }

                let episode = ChapterRoad.EpisodeItem(
                    id: "\(roadIndex)-\(episodeNum)",
                    name: name,
                    src: fullURL,
                    episode: episodeNum
                )
                episodes.append(episode)
                episodeNum += 1
            }

            if !episodes.isEmpty {
                let road = ChapterRoad(
                    id: "road-\(roadIndex)",
                    name: "播放列表\(roadIndex + 1)",
                    episodes: episodes
                )
                roads.append(road)
            }
        }

        if roads.isEmpty, plugin.name.lowercased() == "age" {
            return parseAGEChapters(doc: doc, plugin: plugin)
        }

        return roads
    }

    // MARK: - Helpers

    private func parseAGEChapters(doc: HTMLDocument, plugin: PluginRule) -> [ChapterRoad] {
        var grouped: [Int: [ChapterRoad.EpisodeItem]] = [:]
        var seenURLs = Set<String>()

        for anchor in doc.xpath("//a") {
            let src = extractLink(from: anchor)
            guard isValidPluginPath(src) else { continue }

            let fullURL = buildFullURL(base: plugin.baseURL, path: src)
            guard isLikelyEpisodeURL(src, fullURL: fullURL, plugin: plugin) else { continue }
            guard let parts = URL(string: fullURL)?.path.split(separator: "/").map(String.init),
                  parts.count >= 4,
                  parts[0].lowercased() == "play",
                  let roadNumber = Int(parts[2]),
                  let episodeNumber = Int(parts[3]) else {
                continue
            }

            guard !seenURLs.contains(fullURL) else { continue }
            seenURLs.insert(fullURL)

            let rawName = anchor.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = rawName.isEmpty ? "第 \(episodeNumber) 集" : rawName.replacingOccurrences(
                of: "\\s+",
                with: "",
                options: .regularExpression
            )

            grouped[roadNumber, default: []].append(
                ChapterRoad.EpisodeItem(
                    id: "age-\(roadNumber)-\(episodeNumber)",
                    name: name,
                    src: fullURL,
                    episode: episodeNumber
                )
            )
        }

        return grouped.keys.sorted().map { roadNumber in
            let episodes = (grouped[roadNumber] ?? []).sorted { lhs, rhs in
                if lhs.episode == rhs.episode {
                    return lhs.src < rhs.src
                }
                return lhs.episode < rhs.episode
            }

            return ChapterRoad(
                id: "age-road-\(roadNumber)",
                name: "线路 \(roadNumber)",
                episodes: episodes
            )
        }
    }

    private func scopedXPath(_ xpath: String) -> String {
        let value = xpath.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("//") {
            return "." + value
        }
        if value.hasPrefix("/") {
            return "." + value
        }
        return value
    }

    private func pluginHTTPHeaders(plugin: PluginRule) -> [String: String] {
        var headers: [String: String] = [
            "User-Agent": plugin.userAgent.isEmpty
                ? "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"
                : plugin.userAgent,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
            "Connection": "keep-alive",
            "Referer": plugin.baseURL.hasSuffix("/") ? plugin.baseURL : plugin.baseURL + "/"
        ]

        if let referer = plugin.referer, !referer.isEmpty {
            headers["Referer"] = referer
        }

        return headers
    }

    private func normalizeChapterPageURL(_ pageURL: String, plugin: PluginRule) -> String {
        var value = pageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("http://") {
            value = "https://" + value.dropFirst("http://".count)
        }

        let httpsBase = plugin.baseURL
        let httpBase = plugin.baseURL.replacingOccurrences(of: "https://", with: "http://")
        if value.contains(httpsBase) || value.contains(httpBase) || value.hasPrefix("https://") {
            return value
        }

        return buildFullURL(base: plugin.baseURL, path: value)
    }

    private func extractLink(from element: XMLElement) -> String {
        let attributeNames = ["href", "data-href", "data-url", "data-src", "data-play", "data-link"]

        for name in attributeNames {
            if let value = element.attr(name)?.trimmingCharacters(in: .whitespacesAndNewlines),
               isValidPluginPath(value) {
                return value
            }
        }

        return ""
    }

    private func isValidPluginPath(_ path: String) -> Bool {
        let value = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }

        let lowercased = value.lowercased()
        if lowercased == "#" ||
            lowercased == "/" ||
            lowercased == "." ||
            lowercased.hasPrefix("javascript:") ||
            lowercased.hasPrefix("mailto:") ||
            lowercased.hasPrefix("tel:") {
            return false
        }

        return true
    }

    private func isPluginRootURL(_ url: String, plugin: PluginRule) -> Bool {
        func normalized(_ value: String) -> String {
            var result = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "http://", with: "https://")
                .lowercased()
            while result.hasSuffix("/") {
                result.removeLast()
            }
            return result
        }

        return normalized(url) == normalized(plugin.baseURL)
    }

    private func isLikelyEpisodeURL(_ path: String, fullURL: String, plugin: PluginRule) -> Bool {
        let value = (path + " " + fullURL).lowercased()

        if plugin.name.lowercased() == "age" {
            return value.contains("/play/")
        }

        let episodeMarkers = [
            "/play/",
            "/vodplay/",
            "/episode/",
            "/watch/",
            "playurl",
            "player"
        ]
        return episodeMarkers.contains { value.contains($0) }
    }

    private func buildFullURL(base: String, path: String) -> String {
        if path.hasPrefix("http") {
            return path
        }

        if path.hasPrefix("//") {
            return "https:" + path
        }

        var baseURL = base
        if baseURL.hasSuffix("/") {
            baseURL = String(baseURL.dropLast())
        }

        if path.hasPrefix("/") {
            return baseURL + path
        }

        return baseURL + "/" + path
    }
}

// MARK: - Plugin Error

enum PluginError: LocalizedError {
    case pluginsDirectoryNotFound
    case failedToLoadPlugins
    case invalidURL(String)
    case invalidSharePayload
    case incompatibleAPI(String)
    case repositoryDownloadFailed(String, String)
    case storageUnavailable(String)
    case parsingFailed
    case videoSourceNotFound
    case pluginNotFound(String)

    var errorDescription: String? {
        switch self {
        case .pluginsDirectoryNotFound:
            return "Plugins directory not found in bundle"
        case .failedToLoadPlugins:
            return "Failed to load plugins"
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .invalidSharePayload:
            return "Invalid Kazumi rule payload"
        case .incompatibleAPI(let api):
            return "Rule API \(api) is not compatible with this app"
        case .repositoryDownloadFailed(let fileName, let reason):
            return "Failed to download rule \(fileName): \(reason)"
        case .storageUnavailable(let reason):
            return "Failed to save rules: \(reason)"
        case .parsingFailed:
            return "Failed to parse HTML"
        case .videoSourceNotFound:
            return "Video source not found"
        case .pluginNotFound(let name):
            return "Plugin not found: \(name)"
        }
    }
}

enum PluginMoveDirection {
    case up
    case down
}

enum PluginRepositoryStatus {
    case notInstalled
    case installed
    case updatable

    var actionTitle: String {
        switch self {
        case .notInstalled: return "安装"
        case .installed: return "已安装"
        case .updatable: return "更新"
        }
    }
}

struct PluginTestResult: Equatable {
    let isSuccess: Bool
    let message: String
}

private extension JSONEncoder {
    static var prettyPluginEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
