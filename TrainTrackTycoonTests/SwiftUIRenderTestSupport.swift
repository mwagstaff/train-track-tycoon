import CoreGraphics
import Foundation
import SwiftUI
import UIKit
@testable import TrainTrackTycoon

@MainActor
final class RenderTestSimulationClock: SimulationClock {
    func start(tick: @escaping @MainActor (TimeInterval) -> Void) {}
    func stop() {}
}

/// A fixed environment for CI render smoke tests. Pixel-perfect goldens are deliberately avoided:
/// system fonts, SF Symbols and native control drawing legitimately vary between iOS runtimes.
struct DeterministicRenderHost<Content: View>: View {
    let colorScheme: ColorScheme
    let dynamicTypeSize: DynamicTypeSize
    let content: Content

    init(
        colorScheme: ColorScheme,
        dynamicTypeSize: DynamicTypeSize,
        @ViewBuilder content: () -> Content
    ) {
        self.colorScheme = colorScheme
        self.dynamicTypeSize = dynamicTypeSize
        self.content = content()
    }

    var body: some View {
        ZStack {
            (colorScheme == .dark
                ? Color(red: 0.045, green: 0.055, blue: 0.052)
                : Color(red: 0.96, green: 0.95, blue: 0.90))
                .ignoresSafeArea()
            content
        }
        .environment(\.colorScheme, colorScheme)
        .environment(\.dynamicTypeSize, dynamicTypeSize)
        .environment(\.locale, Locale(identifier: "en_GB"))
        .environment(\.calendar, Self.calendar)
        .environment(\.timeZone, Self.timeZone)
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
    }

    private static var timeZone: TimeZone {
        TimeZone(secondsFromGMT: 0)!
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_GB")
        calendar.timeZone = timeZone
        return calendar
    }
}

@MainActor
enum SwiftUIRenderHarness {
    static func image<Content: View>(
        of content: Content,
        size: CGSize
    ) -> CGImage? {
        let renderer = ImageRenderer(
            content: content
                .frame(width: size.width, height: size.height)
                .clipped()
        )
        renderer.proposedSize = ProposedViewSize(
            width: size.width,
            height: size.height
        )
        renderer.scale = 1
        renderer.isOpaque = true
        return renderer.cgImage
    }

    /// Mounts native controls in UIKit before capture. `ImageRenderer` remains the default, but
    /// ScrollView, Stepper and other UIKit-backed surfaces are not flattened consistently on every
    /// iOS runtime used by the render suite.
    static func hostedImage<Content: View>(
        of content: Content,
        size: CGSize
    ) -> CGImage? {
        let bounds = CGRect(origin: .zero, size: size)
        let controller = UIHostingController(
            rootView: content
                .frame(width: size.width, height: size.height)
                .clipped()
        )
        controller.view.frame = bounds
        controller.view.backgroundColor = .clear

        let window = UIWindow(frame: bounds)
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }

        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        window.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            controller.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        return image.cgImage
    }
}

struct SwiftUIRenderMetrics {
    let opaquePixelFraction: Double
    let meanLuminance: Double
    let luminanceSpan: Double
    let quantizedColorCount: Int

    init?(image: CGImage) {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return nil }

        var opaqueSamples = 0
        var luminanceTotal = 0.0
        var minimumLuminance = 1.0
        var maximumLuminance = 0.0
        var quantizedColors = Set<UInt16>()
        var sampleCount = 0

        // Sampling is sufficient for a blank/contrast smoke check and keeps the test lightweight.
        for pixelIndex in stride(from: 0, to: width * height, by: 17) {
            let byteIndex = pixelIndex * bytesPerPixel
            let red = Double(pixels[byteIndex]) / 255
            let green = Double(pixels[byteIndex + 1]) / 255
            let blue = Double(pixels[byteIndex + 2]) / 255
            let alpha = pixels[byteIndex + 3]
            let luminance = red * 0.2126 + green * 0.7152 + blue * 0.0722

            if alpha >= 250 { opaqueSamples += 1 }
            luminanceTotal += luminance
            minimumLuminance = min(minimumLuminance, luminance)
            maximumLuminance = max(maximumLuminance, luminance)
            sampleCount += 1

            let quantizedRed = UInt16(pixels[byteIndex] >> 5)
            let quantizedGreen = UInt16(pixels[byteIndex + 1] >> 5)
            let quantizedBlue = UInt16(pixels[byteIndex + 2] >> 5)
            quantizedColors.insert((quantizedRed << 6) | (quantizedGreen << 3) | quantizedBlue)
        }

        guard sampleCount > 0 else { return nil }
        opaquePixelFraction = Double(opaqueSamples) / Double(sampleCount)
        meanLuminance = luminanceTotal / Double(sampleCount)
        luminanceSpan = maximumLuminance - minimumLuminance
        quantizedColorCount = quantizedColors.count
    }
}
