//
//  Anime4KWeightedKernelPipeline.swift
//  KazumiTV
//
//  Executes original Anime4K GLSL CNN weights through Core Image kernels.
//  This keeps AVFoundation in charge of frame timing while moving the shader
//  math closer to the original mpv Anime4K implementation.
//

import CoreImage
import Foundation
import Metal

enum Anime4KWeightedKernelPipeline {
    enum KernelSize: Sendable {
        case small
        case medium
    }

    static func restoreSmall(_ image: CIImage) -> CIImage? {
        restore(image, size: .small)
    }

    static func upscaleSmall(_ image: CIImage) -> CIImage? {
        upscale(image, size: .small)
    }

    static func restore(_ image: CIImage, size: KernelSize) -> CIImage? {
        switch size {
        case .small:
            return restoreSmallProgram?.apply(to: image)
        case .medium:
            return restoreMediumProgram?.apply(to: image)
        }
    }

    static func upscale(_ image: CIImage, size: KernelSize) -> CIImage? {
        switch size {
        case .small:
            return upscaleSmallProgram?.apply(to: image)
        case .medium:
            return upscaleMediumProgram?.apply(to: image)
        }
    }

    static func prepareRestore(size: KernelSize) {
        switch size {
        case .small:
            _ = restoreSmallProgram
        case .medium:
            _ = restoreMediumProgram
        }
    }

    static func prepareUpscale(size: KernelSize) {
        switch size {
        case .small:
            _ = upscaleSmallProgram
        case .medium:
            _ = upscaleMediumProgram
        }
    }

    private static let restoreSmallProgram = Anime4KGLSLProgram(resourceName: "Anime4K_Restore_CNN_S")
    private static let upscaleSmallProgram = Anime4KGLSLProgram(resourceName: "Anime4K_Upscale_CNN_x2_S")
    private static let restoreMediumProgram = Anime4KGLSLProgram(resourceName: "Anime4K_Restore_CNN_M")
    private static let upscaleMediumProgram = Anime4KGLSLProgram(resourceName: "Anime4K_Upscale_CNN_x2_M")
}

private final class Anime4KGLSLProgram {
    private let passes: [Anime4KGLSLPass]

    init?(resourceName: String) {
        let shaderURL = Bundle.main.url(
            forResource: resourceName,
            withExtension: "glsl",
            subdirectory: "Shaders"
        ) ?? Bundle.main.url(forResource: resourceName, withExtension: "glsl")

        guard let url = shaderURL,
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            print("Anime4KGLSLProgram: missing bundled shader \(resourceName).glsl")
            return nil
        }

        let parsedPasses = Self.parsePasses(from: source)
        guard !parsedPasses.isEmpty else {
            print("Anime4KGLSLProgram: no usable passes in \(resourceName).glsl")
            return nil
        }
        passes = parsedPasses
    }

    func apply(to image: CIImage) -> CIImage? {
        let normalized = image.normalizedToZeroOrigin()
        var images: [String: CIImage] = ["MAIN": normalized]

        for pass in passes {
            guard let output = pass.apply(images: images) else {
                return nil
            }
            images[pass.outputName] = output
        }

        return images[passes.last?.outputName ?? "MAIN"] ?? images["MAIN"]
    }

    private static func parsePasses(from source: String) -> [Anime4KGLSLPass] {
        let chunks = source
            .components(separatedBy: "\n//!DESC ")
            .dropFirst()
            .map { "//!DESC " + $0 }

        return chunks.enumerated().compactMap { index, chunk in
            let descriptor = chunk.lineStarting(with: "//!DESC") ?? "Anime4K-Pass-\(index)"
            let bindings = chunk.linesStarting(with: "//!BIND ").map {
                String($0.dropFirst("//!BIND ".count)).trimmingCharacters(in: .whitespaces)
            }
            let outputName = chunk.lineStarting(with: "//!SAVE ")
                .map { String($0.dropFirst("//!SAVE ".count)).trimmingCharacters(in: .whitespaces) }
                ?? "MAIN"

            if descriptor.contains("Depth-to-Space") {
                let mainBinding = bindings.first ?? "MAIN"
                let residualBindings = Array(bindings.dropFirst())
                guard !residualBindings.isEmpty else { return nil }

                return Anime4KGLSLPass.depthToSpace(
                    outputName: outputName,
                    mainBinding: mainBinding,
                    residualBindings: residualBindings
                )
            }

            guard let hookRange = chunk.range(of: "vec4 hook()") else {
                return nil
            }

            let bodyStart = chunk.range(of: "#define")?.lowerBound ?? hookRange.lowerBound
            let body = String(chunk[bodyStart...])
            let kernelSource = makeKernelSource(
                passIndex: index,
                bindings: bindings,
                body: body
            )
            return Anime4KGLSLPass(
                outputName: outputName,
                bindings: bindings,
                source: kernelSource
            )
        }
    }

    private static func makeKernelSource(passIndex: Int, bindings: [String], body: String) -> String {
        let arguments = bindings.enumerated()
            .map { "sampler input\($0.offset)" }
            .joined(separator: ", ")

        let samplerMacros = bindings.enumerated().map { index, name in
            """
            #define \(name)_texOff(v) sample(input\(index), samplerTransform(input\(index), destCoord() + v))
            #define \(name)_tex(p) sample(input\(index), samplerTransform(input\(index), p))
            #define \(name)_pos destCoord()
            """
        }.joined(separator: "\n")

        let rewrittenBody = body.replacingOccurrences(
            of: "vec4 hook()",
            with: "kernel vec4 anime4k_pass_\(passIndex)(\(arguments))"
        )

        return """
        \(samplerMacros)
        \(rewrittenBody)
        """
    }
}

private final class Anime4KGLSLPass {
    let outputName: String
    private let bindings: [String]
    private let kernel: CIKernel
    private let kind: Kind

    enum Kind {
        case convolution
        case depthToSpace(mainBinding: String, residualBindings: [String])
    }

    init?(outputName: String, bindings: [String], source: String) {
        guard let kernel = CIKernel.makeKernels(source: source)?.first else {
            print("Anime4KGLSLPass: failed to compile \(outputName)")
            return nil
        }
        self.outputName = outputName
        self.bindings = bindings
        self.kernel = kernel
        kind = .convolution
    }

    private convenience init?(
        outputName: String,
        mainBinding: String,
        residualBindings: [String],
        source: String
    ) {
        self.init(
            outputName: outputName,
            mainBinding: mainBinding,
            residualBindings: residualBindings,
            kernel: Self.makeDepthToSpaceKernel(
                residualCount: residualBindings.count,
                fallbackSource: source
            )
        )
    }

    private init?(
        outputName: String,
        mainBinding: String,
        residualBindings: [String],
        kernel: CIKernel?
    ) {
        guard let kernel else {
            print("Anime4KGLSLPass: failed to compile depth-to-space for \(outputName)")
            return nil
        }
        self.outputName = outputName
        bindings = [mainBinding] + residualBindings
        self.kernel = kernel
        kind = .depthToSpace(mainBinding: mainBinding, residualBindings: residualBindings)
    }

    static func depthToSpace(
        outputName: String,
        mainBinding: String,
        residualBindings: [String]
    ) -> Anime4KGLSLPass? {
        Anime4KGLSLPass(
            outputName: outputName,
            mainBinding: mainBinding,
            residualBindings: residualBindings,
            source: legacyDepthToSpaceSource(residualCount: residualBindings.count)
        )
    }

    private static func makeDepthToSpaceKernel(residualCount: Int, fallbackSource: String) -> CIKernel? {
        if MTLCreateSystemDefaultDevice()?.supportsDynamicLibraries == true,
           let metalKernel = makeMetalDepthToSpaceKernel(residualCount: residualCount) {
            return metalKernel
        }

        return CIKernel.makeKernels(source: fallbackSource)?.first
    }

    private static func makeMetalDepthToSpaceKernel(residualCount: Int) -> CIKernel? {
        do {
            return try CIKernel.kernels(withMetalString: metalDepthToSpaceSource(residualCount: residualCount)).first
        } catch {
            print("Anime4KGLSLPass: failed to compile Metal depth-to-space: \(error)")
            return nil
        }
    }

    private static func legacyDepthToSpaceSource(residualCount: Int) -> String {
        let residualArguments = (0..<residualCount)
            .map { "sampler residualImage\($0)" }
            .joined(separator: ", ")
        let residualSamples = (0..<residualCount)
            .map {
                """
                    vec4 residual\($0) = sample(
                        residualImage\($0),
                        samplerTransform(residualImage\($0), residualCoord)
                    );
                """
            }
            .joined(separator: "\n")
        let residualVector: String
        if residualCount >= 3 {
            residualVector = """
                return base + vec4(
                    anime4k_component(residual0, dc),
                    anime4k_component(residual1, dc),
                    anime4k_component(residual2, dc),
                    anime4k_component(residual2, dc)
                );
            """
        } else {
            residualVector = """
                float value = anime4k_component(residual0, dc);
                return base + vec4(value, value, value, value);
            """
        }

        return """
        float anime4k_component(vec4 residual, vec2 dc) {
            float component = floor(mod(dc.y, 2.0)) * 2.0 + floor(mod(dc.x, 2.0));
            if (component == 1.0) {
                return residual.g;
            }
            if (component == 2.0) {
                return residual.b;
            }
            if (component == 3.0) {
                return residual.a;
            }
            return residual.r;
        }

        kernel vec4 anime4k_depth_to_space(sampler mainImage, \(residualArguments)) {
            vec2 dc = destCoord();
            vec2 sourceCoord = floor(dc * 0.5) + vec2(0.5, 0.5);
            vec2 residualCoord = sourceCoord;
        \(residualSamples)
            vec4 base = sample(
                mainImage,
                samplerTransform(mainImage, sourceCoord)
            );
        \(residualVector)
        }
        """
    }

    private static func metalDepthToSpaceSource(residualCount: Int) -> String {
        let residualArguments = (0..<residualCount)
            .map { "coreimage::sampler residualImage\($0)" }
            .joined(separator: ",\n                ")
        let residualSamples = (0..<residualCount)
            .map {
                """
                    float4 residual\($0) = residualImage\($0).sample(
                        residualImage\($0).transform(residualCoord)
                    );
                """
            }
            .joined(separator: "\n")
        let residualVector: String
        if residualCount >= 3 {
            residualVector = """
                return base + float4(
                    anime4k_component(residual0, dc),
                    anime4k_component(residual1, dc),
                    anime4k_component(residual2, dc),
                    anime4k_component(residual2, dc)
                );
            """
        } else {
            residualVector = """
                float value = anime4k_component(residual0, dc);
                return base + float4(value, value, value, value);
            """
        }

        return """
            #include <CoreImage/CoreImage.h>
            using namespace metal;

            extern "C" { namespace coreimage {
            float anime4k_component(float4 residual, float2 dc) {
                float component = floor(fmod(dc.y, 2.0)) * 2.0 + floor(fmod(dc.x, 2.0));
                if (component == 1.0) {
                    return residual.g;
                }
                if (component == 2.0) {
                    return residual.b;
                }
                if (component == 3.0) {
                    return residual.a;
                }
                return residual.r;
            }

            [[stitchable]] float4 anime4k_depth_to_space(
                coreimage::sampler mainImage,
                \(residualArguments),
                coreimage::destination dest
            ) {
                float2 dc = dest.coord();
                float2 sourceCoord = floor(dc * 0.5) + float2(0.5, 0.5);
                float2 residualCoord = sourceCoord;
            \(residualSamples)
                float4 base = mainImage.sample(mainImage.transform(sourceCoord));
            \(residualVector)
            }
            }}
            """
    }

    func apply(images: [String: CIImage]) -> CIImage? {
        let sourceImages = bindings.compactMap { images[$0] }
        guard sourceImages.count == bindings.count else { return nil }
        let arguments = sourceImages.map { $0.clampedToExtent() }

        let extent: CGRect
        switch kind {
        case .convolution:
            extent = sourceImages[0].extent
        case .depthToSpace:
            let residualExtent = sourceImages[1].extent
            extent = CGRect(
                x: 0,
                y: 0,
                width: residualExtent.width * 2,
                height: residualExtent.height * 2
            )
        }

        guard extent.width > 0, extent.height > 0 else { return nil }

        let output = kernel.apply(
            extent: extent,
            roiCallback: { _, rect in
                rect.insetBy(dx: -1, dy: -1)
            },
            arguments: arguments
        )
        return output?.cropped(to: extent)
    }
}

private extension String {
    func lineStarting(with prefix: String) -> String? {
        split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .first { $0.hasPrefix(prefix) }
    }

    func linesStarting(with prefix: String) -> [String] {
        split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.hasPrefix(prefix) }
    }
}

private extension CIImage {
    func normalizedToZeroOrigin() -> CIImage {
        guard extent.origin != .zero else { return self }
        return transformed(
            by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y)
        )
    }
}
