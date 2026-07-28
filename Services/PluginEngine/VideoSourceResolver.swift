//
//  VideoSourceResolver.swift
//  KazumiTV
//
//  Resolves plugin playback pages entirely on Apple TV. Static and
//  JavaScript-lite pages use NativeVideoResolver; dynamic pages fall back to
//  the side-loaded local WebKit runtime when it is enabled.
//

import Foundation

actor VideoSourceResolver {
    static let shared = VideoSourceResolver()

    private init() {}

    func resolveVideoURL(pageURL: String, plugin: PluginRule) async throws -> VideoSource {
        print(
            "VideoSourceResolver: resolving \(URLLogSanitizer.redacted(pageURL)) "
                + "with local plugin \(plugin.name)"
        )

        let nativeError: Error
        do {
            let source = try await NativeVideoResolver.shared.resolveVideoURL(
                pageURL: pageURL,
                plugin: plugin
            )
            print("VideoSourceResolver: native resolution succeeded: \(URLLogSanitizer.redacted(source.url))")
            return source
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            nativeError = error
            print("VideoSourceResolver: native resolution failed: \(error.localizedDescription)")
        }

        guard SettingsRepository.shared.privateWebResolverEnabled else {
            throw localResolutionError(from: nativeError, plugin: plugin)
        }

        do {
            let source = try await PrivateWebViewResolver.shared.resolveVideoURL(
                pageURL: pageURL,
                plugin: plugin
            )
            print("VideoSourceResolver: local web resolution succeeded: \(URLLogSanitizer.redacted(source.url))")
            return source
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            print("VideoSourceResolver: local web resolution failed: \(error.localizedDescription)")
            throw localResolutionError(from: error, plugin: plugin)
        }
    }

    private func localResolutionError(from error: Error, plugin: PluginRule) -> Error {
        if let sourceError = error as? VideoSourceError {
            switch sourceError {
            case .videoSourceNotFound where plugin.playbackCapability.requiresBrowserRuntime:
                return VideoSourceError.jsRenderedOnly
            default:
                return sourceError
            }
        }

        if let apiError = error as? APIError,
           case .webChallenge(let signal) = apiError {
            switch signal.kind {
            case .challenge:
                return VideoSourceError.challengePage(vendor: signal.vendor)
            case .captcha:
                return VideoSourceError.captchaRequired(vendor: signal.vendor)
            }
        }

        return error
    }
}
