//
//  SettingsRepository.swift
//  KazumiTV
//
//  Settings Repository using UserDefaults
//

import Foundation

final class SettingsRepository {
    static let shared = SettingsRepository()

    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Setting Keys
    enum SettingKey: String {
        // Player
        case hardwareDecoder = "hardwareDecoder"
        case defaultPlaySpeed = "defaultPlaySpeed"
        case playResume = "playResume"
        case autoPlay = "autoPlay"
        case autoPlayNext = "autoPlayNext"
        case displayMode = "displayMode"

        // Danmaku
        case danmakuEnabledByDefault = "danmakuEnabledByDefault"
        case danmakuOpacity = "danmakuOpacity"
        case danmakuFontSize = "danmakuFontSize"
        case danmakuTop = "danmakuTop"
        case danmakuScroll = "danmakuScroll"
        case danmakuBottom = "danmakuBottom"
        case danmakuMassive = "danmakuMassive"
        case danmakuDeduplication = "danmakuDeduplication"
        case danmakuArea = "danmakuArea"
        case danmakuDuration = "danmakuDuration"

        // Theme
        case themeMode = "themeMode"
        case themeColor = "themeColor"
        case oledEnhance = "oledEnhance"

        // Download
        case downloadParallelEpisodes = "downloadParallelEpisodes"
        case downloadParallelSegments = "downloadParallelSegments"
        case downloadDanmaku = "downloadDanmaku"

        // Network
        case proxyEnable = "proxyEnable"
        case proxyUrl = "proxyUrl"
        case privateWebResolverEnable = "privateWebResolverEnable"

        // Display
        case defaultStartupPage = "defaultStartupPage"
        case searchNotShowWatchedBangumis = "searchNotShowWatchedBangumis"
        case searchNotShowAbandonedBangumis = "searchNotShowAbandonedBangumis"
        case timelineNotShowAbandonedBangumis = "timelineNotShowAbandonedBangumis"
        case timelineNotShowWatchedBangumis = "timelineNotShowWatchedBangumis"

        // Private
        case privateMode = "privateMode"
    }

    // MARK: - Generic Accessors

    func getBool(_ key: SettingKey, defaultValue: Bool = false) -> Bool {
        if defaults.object(forKey: key.rawValue) == nil {
            return defaultValue
        }
        return defaults.bool(forKey: key.rawValue)
    }

    func setBool(_ key: SettingKey, _ value: Bool) {
        defaults.set(value, forKey: key.rawValue)
    }

    func getInt(_ key: SettingKey, defaultValue: Int = 0) -> Int {
        if defaults.object(forKey: key.rawValue) == nil {
            return defaultValue
        }
        return defaults.integer(forKey: key.rawValue)
    }

    func setInt(_ key: SettingKey, _ value: Int) {
        defaults.set(value, forKey: key.rawValue)
    }

    func getDouble(_ key: SettingKey, defaultValue: Double = 0) -> Double {
        if defaults.object(forKey: key.rawValue) == nil {
            return defaultValue
        }
        return defaults.double(forKey: key.rawValue)
    }

    func setDouble(_ key: SettingKey, _ value: Double) {
        defaults.set(value, forKey: key.rawValue)
    }

    func getString(_ key: SettingKey, defaultValue: String = "") -> String {
        return defaults.string(forKey: key.rawValue) ?? defaultValue
    }

    func setString(_ key: SettingKey, _ value: String) {
        defaults.set(value, forKey: key.rawValue)
    }

    func getArray(_ key: SettingKey) -> [String] {
        return defaults.stringArray(forKey: key.rawValue) ?? []
    }

    func setArray(_ key: SettingKey, value: [String]) {
        defaults.set(value, forKey: key.rawValue)
    }

    func remove(_ key: SettingKey) {
        defaults.removeObject(forKey: key.rawValue)
    }

    // MARK: - Convenience Properties

    var hardwareDecoder: Bool {
        get { getBool(.hardwareDecoder, defaultValue: true) }
        set { setBool(.hardwareDecoder, newValue) }
    }

    var defaultPlaySpeed: Float {
        get { Float(getDouble(.defaultPlaySpeed, defaultValue: 1.0)) }
        set { setDouble(.defaultPlaySpeed, Double(newValue)) }
    }

    var playResume: Bool {
        get { getBool(.playResume, defaultValue: true) }
        set { setBool(.playResume, newValue) }
    }

    var autoPlay: Bool {
        get { getBool(.autoPlay, defaultValue: true) }
        set { setBool(.autoPlay, newValue) }
    }

    var autoPlayNext: Bool {
        get { getBool(.autoPlayNext, defaultValue: true) }
        set { setBool(.autoPlayNext, newValue) }
    }

    var danmakuEnabledByDefault: Bool {
        get { getBool(.danmakuEnabledByDefault, defaultValue: true) }
        set { setBool(.danmakuEnabledByDefault, newValue) }
    }

    var danmakuOpacity: Double {
        get { getDouble(.danmakuOpacity, defaultValue: 1.0) }
        set { setDouble(.danmakuOpacity, newValue) }
    }

    var danmakuFontSize: Double {
        get { getDouble(.danmakuFontSize, defaultValue: 18.0) }
        set { setDouble(.danmakuFontSize, newValue) }
    }

    var danmakuTop: Bool {
        get { getBool(.danmakuTop, defaultValue: true) }
        set { setBool(.danmakuTop, newValue) }
    }

    var danmakuScroll: Bool {
        get { getBool(.danmakuScroll, defaultValue: true) }
        set { setBool(.danmakuScroll, newValue) }
    }

    var danmakuBottom: Bool {
        get { getBool(.danmakuBottom, defaultValue: true) }
        set { setBool(.danmakuBottom, newValue) }
    }

    var danmakuMassive: Bool {
        get { getBool(.danmakuMassive, defaultValue: false) }
        set { setBool(.danmakuMassive, newValue) }
    }

    var danmakuDeduplication: Bool {
        get { getBool(.danmakuDeduplication, defaultValue: false) }
        set { setBool(.danmakuDeduplication, newValue) }
    }

    var danmakuArea: Double {
        get { getDouble(.danmakuArea, defaultValue: 1.0) }
        set { setDouble(.danmakuArea, newValue) }
    }

    var danmakuDuration: Double {
        get { getDouble(.danmakuDuration, defaultValue: 8.0) }
        set { setDouble(.danmakuDuration, newValue) }
    }

    var themeMode: Int {
        get { getInt(.themeMode, defaultValue: 0) }
        set { setInt(.themeMode, newValue) }
    }

    var downloadParallelEpisodes: Int {
        get { getInt(.downloadParallelEpisodes, defaultValue: 2) }
        set { setInt(.downloadParallelEpisodes, newValue) }
    }

    var downloadParallelSegments: Int {
        get { getInt(.downloadParallelSegments, defaultValue: 3) }
        set { setInt(.downloadParallelSegments, newValue) }
    }

    var downloadDanmaku: Bool {
        get { getBool(.downloadDanmaku, defaultValue: true) }
        set { setBool(.downloadDanmaku, newValue) }
    }

    var privateMode: Bool {
        get { getBool(.privateMode, defaultValue: false) }
        set { setBool(.privateMode, newValue) }
    }

    /// 外部解析服务地址 (仅作为原生解析失败后的后备)
    var serverProxyURL: String {
        get { getString(.proxyUrl, defaultValue: "http://127.0.0.1:5001") }
        set { setString(.proxyUrl, newValue) }
    }

    /// 是否启用外部解析后备服务
    var serverProxyEnabled: Bool {
        get { getBool(.proxyEnable, defaultValue: false) }
        set { setBool(.proxyEnable, newValue) }
    }

    /// 是否启用实验性私有 WebView 解析
    var privateWebResolverEnabled: Bool {
        get { getBool(.privateWebResolverEnable, defaultValue: false) }
        set { setBool(.privateWebResolverEnable, newValue) }
    }

    // MARK: - Reset

    func resetToDefaults() {
        for key in [
            SettingKey.hardwareDecoder,
            .defaultPlaySpeed,
            .playResume,
            .autoPlay,
            .autoPlayNext,
            .danmakuEnabledByDefault,
            .danmakuOpacity,
            .danmakuFontSize,
            .danmakuTop,
            .danmakuScroll,
            .danmakuBottom,
            .danmakuMassive,
            .danmakuDeduplication,
            .danmakuArea,
            .danmakuDuration,
            .themeMode,
            .downloadParallelEpisodes,
            .downloadParallelSegments,
            .downloadDanmaku,
            .privateMode,
            .proxyEnable,
            .proxyUrl,
            .privateWebResolverEnable
        ] {
            remove(key)
        }
    }
}
