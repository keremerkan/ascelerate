import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ScreenshotFramer: Sendable {
    let config: ScreenshotConfig

    /// Frame all screenshots for all languages. Used by `screenshot frame` subcommand.
    func frameAll() throws {
        let bezels = loadBezels()
        guard !bezels.isEmpty else { return }

        for language in config.languages {
            frameLanguage(language, bezels: bezels)
        }

        printFramingSummary()
    }

    /// Frame screenshots for a single language. Used by the runner after each language completes.
    func frameLanguage(_ language: String, bezels: [(device: ScreenshotConfig.Device, image: CGImage)]) {
        let outputDir = URL(fileURLWithPath: config.outputDirectory)
        let framedDir = resolvedFramedDir()
        let langDir = outputDir.appendingPathComponent(language)
        let framedLangDir = framedDir.appendingPathComponent(language)

        guard FileManager.default.fileExists(atPath: langDir.path) else { return }
        try? FileManager.default.createDirectory(at: framedLangDir, withIntermediateDirectories: true)

        for (device, bezelImage) in bezels {
            let prefix = device.simulator + "-"
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: langDir, includingPropertiesForKeys: nil
            ) else { continue }

            let screenshots = files.filter {
                $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension.lowercased() == "png"
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }

            guard !screenshots.isEmpty else { continue }

            var deviceFramed = 0
            for file in screenshots {
                autoreleasepool {
                    let outputURL = framedLangDir.appendingPathComponent(file.lastPathComponent)
                    do {
                        guard let screenshotImage = Self.loadImage(from: file) else {
                            throw ScreenshotError.framingFailed("Failed to load: \(file.lastPathComponent)")
                        }
                        guard let result = Self.composite(screenshot: screenshotImage, bezel: bezelImage) else {
                            throw ScreenshotError.framingFailed("Compositing failed: \(file.lastPathComponent)")
                        }
                        try Self.writePNG(result, to: outputURL)
                        deviceFramed += 1
                    } catch {
                        print("  [\(device.simulator)] " + red("\(error)"))
                    }
                }
            }

            if deviceFramed > 0 {
                print("  [\(device.simulator)] Framed \(deviceFramed) screenshot(s) → \(language)/")
            }
        }
    }

    /// Load bezels for all devices with framing enabled. Prints errors for missing/invalid bezels.
    func loadBezels() -> [(device: ScreenshotConfig.Device, image: CGImage)] {
        let devices = config.devices.filter { $0.frameDevice == true }
        guard !devices.isEmpty else { return [] }

        var loaded: [(device: ScreenshotConfig.Device, image: CGImage)] = []
        for device in devices {
            guard let bezelPath = device.deviceBezel else {
                print("  [\(device.simulator)] " + red("No deviceBezel path configured, skipping"))
                continue
            }
            let resolved = URL(fileURLWithPath: bezelPath).path
            guard FileManager.default.fileExists(atPath: resolved) else {
                print("  [\(device.simulator)] " + red("Bezel not found: \(bezelPath)"))
                continue
            }
            guard let image = Self.loadImage(from: URL(fileURLWithPath: resolved)) else {
                print("  [\(device.simulator)] " + red("Failed to load bezel: \(bezelPath)"))
                continue
            }
            loaded.append((device, image))
        }

        if loaded.isEmpty {
            print("  No bezels loaded, skipping framing.")
        }

        return loaded
    }

    func printFramingSummary() {
        let framedPath = config.framedOutputDirectory ?? config.outputDirectory + "/framed"
        let framedDir = resolvedFramedDir()

        // Count framed files across all languages
        var total = 0
        for language in config.languages {
            let langDir = framedDir.appendingPathComponent(language)
            if let files = try? FileManager.default.contentsOfDirectory(at: langDir, includingPropertiesForKeys: nil) {
                total += files.filter { $0.pathExtension.lowercased() == "png" }.count
            }
        }

        if total > 0 {
            print("\n" + green("Framed") + " \(total) screenshot(s) → \(framedPath)")
        }
    }

    private func resolvedFramedDir() -> URL {
        if let custom = config.framedOutputDirectory {
            return URL(fileURLWithPath: custom)
        }
        return URL(fileURLWithPath: config.outputDirectory).appendingPathComponent("framed")
    }

    // MARK: - Image Loading

    static func loadImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: - Compositing

    static func composite(screenshot: CGImage, bezel: CGImage) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: nil,
            width: bezel.width,
            height: bezel.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }

        let bezelRect = CGRect(x: 0, y: 0, width: bezel.width, height: bezel.height)

        // Find the screen area within the bezel
        let screenRect = findScreenArea(in: bezel) ?? CGRect(
            x: (bezel.width - screenshot.width) / 2,
            y: (bezel.height - screenshot.height) / 2,
            width: screenshot.width,
            height: screenshot.height
        )

        // Clip screenshot to bezel shape (handles rounded corners) using save/restore
        // instead of a separate context to reduce peak memory
        if let matte = createMatte(from: bezel) {
            context.saveGState()
            context.clip(to: bezelRect, mask: matte)
            context.draw(screenshot, in: screenRect)
            context.restoreGState()
        } else {
            context.draw(screenshot, in: screenRect)
        }

        // Draw the device bezel frame on top
        context.draw(bezel, in: bezelRect)

        return context.makeImage()
    }

    // MARK: - Screen Area Detection

    /// Finds the transparent screen area within a device bezel by scanning outward from center.
    /// Returns a CGRect in lower-left-origin coordinates for use with CGContext.
    static func findScreenArea(in bezel: CGImage) -> CGRect? {
        guard bezel.bitsPerPixel == 32,
              let data = bezel.dataProvider?.data,
              let pointer = CFDataGetBytePtr(data) else { return nil }

        let w = bezel.width
        let h = bezel.height
        let bpr = bezel.bytesPerRow
        let cx = w / 2
        let cy = h / 2

        func isOpaque(_ x: Int, _ y: Int) -> Bool {
            pointer[y * bpr + x * 4 + 3] == 255
        }

        func scanY(x: Int, from y0: Int, toward target: Int) -> Int? {
            let step = target > y0 ? 1 : -1
            var y = y0
            while y != target + step {
                if isOpaque(x, y) { return y }
                y += step
            }
            return nil
        }

        func scanX(y: Int, from x0: Int, toward target: Int) -> Int? {
            let step = target > x0 ? 1 : -1
            var x = x0
            while x != target + step {
                if isOpaque(x, y) { return x }
                x += step
            }
            return nil
        }

        // Find initial bezel edges from center
        guard let topEdge = scanY(x: cx, from: cy, toward: 0),
              let bottomEdge = scanY(x: cx, from: cy, toward: h - 1),
              let leftEdge = scanX(y: cy, from: cx, toward: 0),
              let rightEdge = scanX(y: cy, from: cx, toward: w - 1)
        else { return nil }

        // Screen area is just inside the bezel edges
        var screenTop = topEdge + 1
        var screenBottom = bottomEdge - 1
        var screenLeft = leftEdge + 1
        var screenRight = rightEdge - 1

        // Refine Y bounds by scanning across the X range
        for x in screenLeft...screenRight {
            if let edge = scanY(x: x, from: cy, toward: 0) {
                screenTop = min(screenTop, edge + 1)
            }
            if let edge = scanY(x: x, from: cy, toward: h - 1) {
                screenBottom = max(screenBottom, edge - 1)
            }
        }

        // Refine X bounds by scanning across the Y range
        for y in screenTop...screenBottom {
            if let edge = scanX(y: y, from: cx, toward: 0) {
                screenLeft = min(screenLeft, edge + 1)
            }
            if let edge = scanX(y: y, from: cx, toward: w - 1) {
                screenRight = max(screenRight, edge - 1)
            }
        }

        let screenWidth = screenRight - screenLeft + 1
        let screenHeight = screenBottom - screenTop + 1
        let flippedY = h - screenTop - screenHeight

        return CGRect(x: screenLeft, y: flippedY, width: screenWidth, height: screenHeight)
    }

    // MARK: - Matte

    /// Creates a grayscale mask: white between leftmost/rightmost opaque pixels per scanline,
    /// black elsewhere. Used to clip the screenshot to the bezel's screen shape.
    private static func createMatte(from bezel: CGImage) -> CGImage? {
        guard bezel.bitsPerPixel == 32,
              let data = bezel.dataProvider?.data,
              let pointer = CFDataGetBytePtr(data) else { return nil }

        let w = bezel.width
        let h = bezel.height
        let bpr = bezel.bytesPerRow

        guard let context = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue).rawValue
        ) else { return nil }

        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))

        context.setFillColor(gray: 1, alpha: 1)
        for y in 0..<h {
            var lineMinX: Int?
            var lineMaxX: Int?

            for x in 0..<w {
                if pointer[y * bpr + x * 4 + 3] == 255 {
                    if lineMinX == nil { lineMinX = x }
                    lineMaxX = x
                }
            }

            if let minX = lineMinX, let maxX = lineMaxX {
                let drawY = h - 1 - y
                context.fill(CGRect(x: minX, y: drawY, width: maxX - minX + 1, height: 1))
            }
        }

        return context.makeImage()
    }

    // MARK: - PNG Writing

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw ScreenshotError.framingFailed("Failed to create image destination: \(url.path)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotError.framingFailed("Failed to write: \(url.path)")
        }
    }
}
