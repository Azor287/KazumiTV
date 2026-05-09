//
//  SuperResolutionMode.swift
//  KazumiTV
//
//  Player super-resolution modes matching Kazumi's OFF plus two Anime4K-inspired
//  native Core Image tiers.
//

import Foundation

enum SuperResolutionMode: Int, CaseIterable, Identifiable, Sendable {
    case off = 1
    case efficiency = 2
    case quality = 3

    static var allCases: [SuperResolutionMode] {
        [.off, .efficiency, .quality]
    }

    var id: Int { rawValue }

    var isEnabled: Bool {
        self != .off
    }

    var requiresPerformanceWarning: Bool {
        switch self {
        case .off:
            return false
        case .quality, .efficiency:
            return true
        }
    }

    var title: String {
        switch self {
        case .off:
            return "关闭"
        case .efficiency:
            return "1440p 轻量增强"
        case .quality:
            return "1440p M/S 权重超分"
        }
    }

    var playerTitle: String {
        switch self {
        case .off:
            return "超分 关"
        case .efficiency:
            return "超分 轻量增强"
        case .quality:
            return "超分 M/S权重"
        }
    }

    var settingsDescription: String {
        switch self {
        case .off:
            return "默认禁用超分辨率"
        case .efficiency:
            return "高光压制 + 降噪锐化 + Lanczos，最高 1440p"
        case .quality:
            return "Restore CNN M/S + Upscale CNN M/S，最高 1440p"
        }
    }

    var originalAnime4KShaderChain: [String] {
        switch self {
        case .off:
            return []
        case .efficiency:
            return [
                "Anime4K_Clamp_Highlights",
                "CINoiseReduction",
                "CIUnsharpMask",
                "CISharpenLuminance",
                "CILanczosScaleTransform",
                "Anime4K_Clamp_Highlights"
            ]
        case .quality:
            return [
                "Anime4K_Clamp_Highlights",
                "Anime4K_Restore_CNN_M",
                "Anime4K_Restore_CNN_S",
                "Anime4K_Upscale_CNN_x2_M",
                "Anime4K_AutoDownscalePre_x2",
                "Anime4K_AutoDownscalePre_x4",
                "Anime4K_Upscale_CNN_x2_S"
            ]
        }
    }

    var previous: SuperResolutionMode? {
        guard let index = Self.allCases.firstIndex(of: self), index > 0 else {
            return nil
        }
        return Self.allCases[index - 1]
    }

    var next: SuperResolutionMode? {
        guard let index = Self.allCases.firstIndex(of: self),
              index < Self.allCases.count - 1 else {
            return nil
        }
        return Self.allCases[index + 1]
    }

    var cycledForward: SuperResolutionMode {
        next ?? .off
    }
}
