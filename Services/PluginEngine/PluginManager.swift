//
//  PluginManager.swift
//  KazumiTV
//
//  Plugin Manager - loads and manages scraping plugins
//

import Foundation
import Fuzi

actor PluginManager {
    static let shared = PluginManager()

    private let repositoryBaseURLs = [
        "https://raw.githubusercontent.com/Predidit/KazumiRules/main/",
        "https://cdn.jsdelivr.net/gh/Predidit/KazumiRules@main/",
    ]
    private let maxSupportedAPILevel = 6
    private let pluginsFileName = "plugins.json"
    private let repositoryHeaders = [
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15",
        "Accept": "application/json,text/plain,*/*",
    ]

    private var plugins: [PluginRule] = []
    private var pluginsByName: [String: PluginRule] = [:]

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

        let bundledRules = try loadBundledPlugins()
        try savePlugins(bundledRules)
        setPlugins(bundledRules)

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
        plugins = rules
        pluginsByName = [:]
        for rule in rules {
            pluginsByName[rule.name] = rule
        }
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
        let bundledRules = try loadBundledPlugins()
        try savePlugins(bundledRules)
        setPlugins(bundledRules)
    }

    func importSharedPlugin(_ value: String) async throws -> PluginRule {
        let plugin = try PluginRule.decodeShareURL(value.trimmingCharacters(in: .whitespacesAndNewlines))
        try await upsertPlugin(plugin)
        return plugin
    }

    // MARK: - Rule Repository

    func fetchRepositoryIndex() async throws -> [PluginRepositoryItem] {
        let data = try await downloadRepositoryFile(fileName: "index.json", pluginName: nil)
        return try JSONDecoder().decode([PluginRepositoryItem].self, from: data)
    }

    func fetchRepositoryPlugin(name: String) async throws -> PluginRule {
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let data = try await downloadRepositoryFile(fileName: encodedName + ".json", pluginName: name)
        let plugin = try JSONDecoder().decode(PluginRule.self, from: data)
        guard Int(plugin.api) ?? 0 <= maxSupportedAPILevel else {
            throw PluginError.incompatibleAPI(plugin.api)
        }
        return plugin
    }

    private func downloadRepositoryFile(fileName: String, pluginName: String?) async throws -> Data {
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

        if SettingsRepository.shared.serverProxyEnabled {
            do {
                let serverAPI = ServerAPI.shared
                if let pluginName {
                    return try await serverAPI.fetchRuleRepositoryPlugin(name: pluginName)
                }
                return try await serverAPI.fetchRuleRepositoryIndex()
            } catch {
                let message = error.localizedDescription
                failureMessages.append("server proxy: \(message)")
                print("PluginManager: 规则仓库服务器代理失败 \(fileName): \(message)")
            }
        }

        throw PluginError.repositoryDownloadFailed(fileName, failureMessages.joined(separator: "; "))
    }

    func installRepositoryPlugin(name: String) async throws -> PluginRule {
        let plugin = try await fetchRepositoryPlugin(name: name)
        try await upsertPlugin(plugin)
        return plugin
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
        let activePlugins = plugins

        return await withTaskGroup(of: [SearchItem].self) { group in
            for plugin in activePlugins {
                group.addTask {
                    do {
                        return try await Self.searchWithPluginRule(plugin: plugin, keyword: keyword)
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

    /// Search using a specific plugin
    func searchWithPlugin(plugin: PluginRule, keyword: String) async throws -> [SearchItem] {
        try await Self.searchWithPluginRule(plugin: plugin, keyword: keyword)
    }

    private static func searchWithPluginRule(plugin: PluginRule, keyword: String) async throws -> [SearchItem] {
        let api = APIClient.shared

        let searchURL = plugin.buildSearchURL(keyword: keyword)
        guard let url = URL(string: searchURL) else {
            throw PluginError.invalidURL(searchURL)
        }

        let headers = searchHTTPHeaders(for: plugin)
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

    private static func searchHTTPHeaders(for plugin: PluginRule) -> [String: String] {
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
