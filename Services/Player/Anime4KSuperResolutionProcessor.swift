//
//  Anime4KSuperResolutionProcessor.swift
//  KazumiTV
//
//  Anime4K-inspired Core Image pipeline used inside AVFoundation's video
//  composition clock. It follows the original Kazumi OFF/Efficiency/Quality
//  model without taking frame timing away from AVPlayer.
//

import AVFoundation
import CoreImage
import Foundation

enum Anime4KSuperResolutionProcessor {
    static func prepare(mode: SuperResolutionMode) {
        guard let profile = Profile(mode: mode) else { return }

        for kernelSize in profile.weightedRestoreChain {
            Anime4KWeightedKernelPipeline.prepareRestore(size: kernelSize)
        }
        if let firstUpscaleKernel = profile.firstUpscaleKernel {
            Anime4KWeightedKernelPipeline.prepareUpscale(size: firstUpscaleKernel)
        }
        if let finalUpscaleKernel = profile.finalUpscaleKernel,
           profile.maximumFinalUpscalePixels > 0 {
            Anime4KWeightedKernelPipeline.prepareUpscale(size: finalUpscaleKernel)
        }
    }

    static func preferredRenderSize(from sourceSize: CGSize, mode: SuperResolutionMode) -> CGSize {
        guard let profile = Profile(mode: mode),
              sourceSize.width > 0,
              sourceSize.height > 0 else {
            return sourceSize
        }

        let sourcePixels = sourceSize.width * sourceSize.height
        guard sourcePixels > 0 else { return sourceSize }

        let maxScale = sqrt(profile.maximumRenderPixels / sourcePixels)
        let desiredScale = desiredUpscaleFactor(for: sourceSize, profile: profile)
        let scale = max(1, min(desiredScale, maxScale))
        guard scale > 1.01 else { return sourceSize }

        return CGSize(
            width: roundedEven(sourceSize.width * scale),
            height: roundedEven(sourceSize.height * scale)
        )
    }

    static func requiresVideoComposition(from sourceSize: CGSize, mode: SuperResolutionMode) -> Bool {
        guard let profile = Profile(mode: mode) else { return false }

        let renderSize = preferredRenderSize(from: sourceSize, mode: mode)
        if abs(renderSize.width - sourceSize.width) > 1 ||
            abs(renderSize.height - sourceSize.height) > 1 {
            return true
        }

        let sourcePixels = sourceSize.width * sourceSize.height
        return profile.hasFrameProcessing && sourcePixels <= profile.maximumRenderPixels
    }

    static func process(_ request: AVAsynchronousCIImageFilteringRequest, mode: SuperResolutionMode) {
        guard let profile = Profile(mode: mode) else {
            request.finish(with: request.sourceImage, context: nil)
            return
        }

        let sourceExtent = request.sourceImage.extent
        let renderSize = validRenderSize(request.renderSize, fallback: sourceExtent.size)
        let renderExtent = CGRect(origin: .zero, size: renderSize)

        var image = normalize(request.sourceImage)
        image = clampHighlights(image, profile: profile)

        if let restored = weightedRestore(image, profile: profile) {
            image = restored
        } else {
            image = restore(
                image,
                profile: profile,
                passCount: profile.restorePassesBeforeUpscale,
                isPostUpscale: false
            )
        }

        if let firstUpscaleKernel = profile.firstUpscaleKernel,
           shouldApplyWeightedUpscale(
            image,
            sourceSize: sourceExtent.size,
            renderSize: renderExtent.size,
            profile: profile
           ),
           let upscaled = Anime4KWeightedKernelPipeline.upscale(image, size: firstUpscaleKernel) {
            image = applyAutoDownscalePre(
                upscaled,
                nativeSize: sourceExtent.size,
                outputSize: renderExtent.size
            )

            if let finalUpscaleKernel = profile.finalUpscaleKernel,
               canApplyFinalUpscale(image, profile: profile),
               let finalUpscaled = Anime4KWeightedKernelPipeline.upscale(image, size: finalUpscaleKernel) {
                image = finalUpscaled
            }

            image = fit(image, to: renderExtent)
        } else {
            image = upscale(image, to: renderExtent, profile: profile)
        }

        if profile.restorePassesAfterUpscale > 0 {
            image = restore(
                image,
                profile: profile,
                passCount: profile.restorePassesAfterUpscale,
                isPostUpscale: true
            )
        }
        image = clampHighlights(image, profile: profile)
        image = finish(image, profile: profile)

        request.finish(with: image.cropped(to: renderExtent), context: nil)
    }
}

private extension Anime4KSuperResolutionProcessor {
    struct Profile {
        let maximumRenderPixels: CGFloat
        let lowResolutionUpscaleFactor: CGFloat
        let regularUpscaleFactor: CGFloat
        let restorePassesBeforeUpscale: Int
        let restorePassesAfterUpscale: Int
        let highlightAmount: CGFloat
        let noiseLevel: CGFloat
        let noiseSharpness: CGFloat
        let unsharpRadius: CGFloat
        let unsharpIntensity: CGFloat
        let luminanceSharpness: CGFloat
        let postUnsharpRadius: CGFloat
        let postUnsharpIntensity: CGFloat
        let postLuminanceSharpness: CGFloat
        let finishingLuminanceSharpness: CGFloat
        let weightedRestoreChain: [Anime4KWeightedKernelPipeline.KernelSize]
        let firstUpscaleKernel: Anime4KWeightedKernelPipeline.KernelSize?
        let finalUpscaleKernel: Anime4KWeightedKernelPipeline.KernelSize?
        let minimumWeightedUpscaleScale: CGFloat
        let maximumFirstUpscalePixels: CGFloat
        let maximumFinalUpscalePixels: CGFloat

        var hasFrameProcessing: Bool {
            !weightedRestoreChain.isEmpty ||
                firstUpscaleKernel != nil ||
                finalUpscaleKernel != nil ||
                restorePassesBeforeUpscale > 0 ||
                restorePassesAfterUpscale > 0 ||
                highlightAmount < 0.999 ||
                finishingLuminanceSharpness > 0.001
        }

        init?(mode: SuperResolutionMode) {
            switch mode {
            case .off:
                return nil
            case .efficiency:
                maximumRenderPixels = 2560 * 1440
                lowResolutionUpscaleFactor = 4
                regularUpscaleFactor = 2
                restorePassesBeforeUpscale = 1
                restorePassesAfterUpscale = 0
                highlightAmount = 0.92
                noiseLevel = 0.015
                noiseSharpness = 0.42
                unsharpRadius = 0.48
                unsharpIntensity = 0.24
                luminanceSharpness = 0.16
                postUnsharpRadius = 0.42
                postUnsharpIntensity = 0.18
                postLuminanceSharpness = 0.10
                finishingLuminanceSharpness = 0
                weightedRestoreChain = []
                firstUpscaleKernel = nil
                finalUpscaleKernel = nil
                minimumWeightedUpscaleScale = 1.01
                maximumFirstUpscalePixels = 2560 * 1440
                maximumFinalUpscalePixels = 0
            case .quality:
                maximumRenderPixels = 2560 * 1440
                lowResolutionUpscaleFactor = 4
                regularUpscaleFactor = 2
                restorePassesBeforeUpscale = 2
                restorePassesAfterUpscale = 0
                highlightAmount = 0.88
                noiseLevel = 0.018
                noiseSharpness = 0.55
                unsharpRadius = 0.56
                unsharpIntensity = 0.32
                luminanceSharpness = 0.22
                postUnsharpRadius = 0.48
                postUnsharpIntensity = 0.24
                postLuminanceSharpness = 0.14
                finishingLuminanceSharpness = 0
                weightedRestoreChain = [.medium, .small]
                firstUpscaleKernel = .medium
                finalUpscaleKernel = .small
                minimumWeightedUpscaleScale = 1.01
                maximumFirstUpscalePixels = 2560 * 1440
                maximumFinalUpscalePixels = maximumRenderPixels * 2
            }
        }
    }

    static func weightedRestore(_ image: CIImage, profile: Profile) -> CIImage? {
        guard !profile.weightedRestoreChain.isEmpty else { return nil }

        var output = image
        for kernelSize in profile.weightedRestoreChain {
            guard let restored = Anime4KWeightedKernelPipeline.restore(output, size: kernelSize) else {
                return nil
            }
            output = restored
        }
        return output
    }

    static func shouldApplyWeightedUpscale(
        _ image: CIImage,
        sourceSize: CGSize,
        renderSize: CGSize,
        profile: Profile
    ) -> Bool {
        guard sourceSize.width > 0,
              sourceSize.height > 0,
              renderSize.width > 0,
              renderSize.height > 0,
              image.extent.width > 0,
              image.extent.height > 0 else {
            return false
        }

        let targetScale = min(renderSize.width / sourceSize.width, renderSize.height / sourceSize.height)
        guard targetScale >= profile.minimumWeightedUpscaleScale else {
            return false
        }

        let firstUpscalePixels = image.extent.width * 2 * image.extent.height * 2
        return firstUpscalePixels <= profile.maximumFirstUpscalePixels
    }

    static func desiredUpscaleFactor(for size: CGSize, profile: Profile) -> CGFloat {
        let longEdge = max(size.width, size.height)
        return longEdge <= 1440 ? profile.lowResolutionUpscaleFactor : profile.regularUpscaleFactor
    }

    static func applyAutoDownscalePre(
        _ image: CIImage,
        nativeSize: CGSize,
        outputSize: CGSize
    ) -> CIImage {
        guard nativeSize.width > 0,
              nativeSize.height > 0,
              outputSize.width > 0,
              outputSize.height > 0 else {
            return image
        }

        let scaleX = outputSize.width / nativeSize.width
        let scaleY = outputSize.height / nativeSize.height

        if scaleX < 4.0,
           scaleY < 4.0,
           scaleX > 2.4,
           scaleY > 2.4 {
            return resize(image, to: CGSize(width: outputSize.width / 2, height: outputSize.height / 2))
        }

        if scaleX < 2.0,
           scaleY < 2.0,
           scaleX > 1.2,
           scaleY > 1.2 {
            return resize(image, to: outputSize)
        }

        return image
    }

    static func canApplyFinalUpscale(_ image: CIImage, profile: Profile) -> Bool {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return false }

        let finalPixels = extent.width * 2 * extent.height * 2
        return finalPixels <= profile.maximumFinalUpscalePixels
    }

    static func validRenderSize(_ size: CGSize, fallback: CGSize) -> CGSize {
        if size.width > 0, size.height > 0 {
            return size
        }
        return CGSize(width: max(1, fallback.width), height: max(1, fallback.height))
    }

    static func roundedEven(_ value: CGFloat) -> CGFloat {
        max(2, (value / 2).rounded(.toNearestOrAwayFromZero) * 2)
    }

    static func normalize(_ image: CIImage) -> CIImage {
        let extent = image.extent
        guard extent.origin != .zero else { return image }
        return image.transformed(
            by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y)
        )
    }

    static func upscale(_ image: CIImage, to renderExtent: CGRect, profile: Profile) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }

        let scale = min(renderExtent.width / extent.width, renderExtent.height / extent.height)
        var output = filtered(
            "CILanczosScaleTransform",
            image: image,
            parameters: [
                kCIInputScaleKey: scale,
                kCIInputAspectRatioKey: 1.0
            ]
        )

        let scaledExtent = output.extent
        let offsetX = renderExtent.midX - scaledExtent.midX
        let offsetY = renderExtent.midY - scaledExtent.midY
        output = output.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))

        return output.clampedToExtent().cropped(to: renderExtent)
    }

    static func fit(_ image: CIImage, to renderExtent: CGRect) -> CIImage {
        let extent = image.extent
        guard extent.width > 0,
              extent.height > 0,
              extent.size != renderExtent.size else {
            return image.cropped(to: renderExtent)
        }

        let scale = min(renderExtent.width / extent.width, renderExtent.height / extent.height)
        let scaled = filtered(
            "CILanczosScaleTransform",
            image: image.cropped(to: extent),
            parameters: [
                kCIInputScaleKey: scale,
                kCIInputAspectRatioKey: 1.0
            ]
        )
        let offsetX = renderExtent.midX - scaled.extent.midX
        let offsetY = renderExtent.midY - scaled.extent.midY
        return scaled
            .transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
            .cropped(to: renderExtent)
    }

    static func resize(_ image: CIImage, to size: CGSize) -> CIImage {
        let extent = image.extent
        guard extent.width > 0,
              extent.height > 0,
              size.width > 0,
              size.height > 0 else {
            return image
        }

        let targetExtent = CGRect(origin: .zero, size: size)
        let scale = min(size.width / extent.width, size.height / extent.height)
        let scaled = filtered(
            "CILanczosScaleTransform",
            image: image.cropped(to: extent),
            parameters: [
                kCIInputScaleKey: scale,
                kCIInputAspectRatioKey: 1.0
            ]
        )
        let offsetX = targetExtent.midX - scaled.extent.midX
        let offsetY = targetExtent.midY - scaled.extent.midY
        return scaled
            .transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
            .cropped(to: targetExtent)
    }

    static func clampHighlights(_ image: CIImage, profile: Profile) -> CIImage {
        guard profile.highlightAmount < 0.999 else {
            return image
        }

        let extent = image.extent
        let output = filtered(
            "CIHighlightShadowAdjust",
            image: image.clampedToExtent(),
            parameters: [
                "inputHighlightAmount": profile.highlightAmount,
                "inputShadowAmount": 0.0
            ]
        )
        return output.cropped(to: extent)
    }

    static func restore(
        _ image: CIImage,
        profile: Profile,
        passCount: Int,
        isPostUpscale: Bool
    ) -> CIImage {
        guard passCount > 0 else { return image }

        var output = image
        for _ in 0..<passCount {
            let extent = output.extent
            let unsharpRadius = isPostUpscale ? profile.postUnsharpRadius : profile.unsharpRadius
            let unsharpIntensity = isPostUpscale ? profile.postUnsharpIntensity : profile.unsharpIntensity
            let luminanceSharpness = isPostUpscale ? profile.postLuminanceSharpness : profile.luminanceSharpness

            output = filtered(
                "CINoiseReduction",
                image: output.clampedToExtent(),
                parameters: [
                    "inputNoiseLevel": profile.noiseLevel,
                    "inputSharpness": profile.noiseSharpness
                ]
            ).cropped(to: extent)

            output = filtered(
                "CIUnsharpMask",
                image: output.clampedToExtent(),
                parameters: [
                    kCIInputRadiusKey: unsharpRadius,
                    kCIInputIntensityKey: unsharpIntensity
                ]
            ).cropped(to: extent)

            output = filtered(
                "CISharpenLuminance",
                image: output.clampedToExtent(),
                parameters: [kCIInputSharpnessKey: luminanceSharpness]
            ).cropped(to: extent)
        }

        return output
    }

    static func finish(_ image: CIImage, profile: Profile) -> CIImage {
        guard profile.finishingLuminanceSharpness > 0.001 else {
            return image
        }

        let extent = image.extent
        return filtered(
            "CISharpenLuminance",
            image: image.clampedToExtent(),
            parameters: [kCIInputSharpnessKey: profile.finishingLuminanceSharpness]
        ).cropped(to: extent)
    }

    static func filtered(
        _ name: String,
        image: CIImage,
        parameters: [String: Any]
    ) -> CIImage {
        guard let filter = CIFilter(name: name) else { return image }

        filter.setValue(image, forKey: kCIInputImageKey)
        for (key, value) in parameters where filter.inputKeys.contains(key) {
            filter.setValue(value, forKey: key)
        }
        return filter.outputImage ?? image
    }
}
