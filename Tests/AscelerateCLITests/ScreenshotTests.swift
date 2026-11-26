import CoreGraphics
import Foundation
import Testing
@testable import ascelerate

/// The screenshot module's pure parts: config key checks and bezel framing.
@Suite struct ScreenshotTests {
  @Test func unknownKeysAreRefusedWithTheNearestKnownOne() throws {
    let known = ["scheme", "devices", "numberOfRetries", "languages"]
    try ScreenshotConfig.checkKeys("scheme: A\nlanguages: [en-US]\n", known: known)
    #expect(ScreenshotConfig.nearest("numberOfRetrys", among: known) == "numberOfRetries")
    #expect(ScreenshotConfig.nearest("SCHEME", among: known) == "scheme")
    #expect(throws: (any Error).self) { try ScreenshotConfig.checkKeys("numberOfRetrys: 2\n", known: known) }
    // A device's keys are checked against the device keys.
    #expect(throws: (any Error).self) {
      try ScreenshotConfig.checkKeys("devices:\n  - simulator: iPhone\n    deviceBezle: a.png\n", known: known)
    }
    try ScreenshotConfig.checkKeys("devices:\n  - simulator: iPhone\n    deviceBezel: a.png\n", known: known)
  }

  /// An opaque frame with a transparent screen hole of `screen`'s size, `border` px around it.
  func bezel(screen: (Int, Int), border: Int = 20) -> CGImage {
    let (w, h) = (screen.0 + 2 * border, screen.1 + 2 * border)
    let context = CGContext(
      data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: w, height: h))
    context.clear(CGRect(x: border, y: border, width: screen.0, height: screen.1))
    return context.makeImage()!
  }

  func shot(_ w: Int, _ h: Int) -> CGImage {
    let context = CGContext(
      data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return context.makeImage()!
  }

  @Test func theScreenAreaIsTheTransparentHole() throws {
    let area = try #require(ScreenshotFramer.findScreenArea(in: bezel(screen: (300, 600))))
    #expect(abs(area.width - 300) <= 2 && abs(area.height - 600) <= 2)
  }

  @Test func eachShotGetsTheClosestBezel() {
    let folded = ScreenshotFramer.Bezel(image: bezel(screen: (140, 200)), screen: CGSize(width: 140, height: 200))
    let unfolded = ScreenshotFramer.Bezel(image: bezel(screen: (285, 200)), screen: CGSize(width: 285, height: 200))
    let portrait = ScreenshotFramer.Bezel(image: bezel(screen: (200, 400)), screen: CGSize(width: 200, height: 400))
    #expect(ScreenshotFramer.bestBezel(for: shot(140, 200), among: [folded, unfolded]) === folded.image)
    #expect(ScreenshotFramer.bestBezel(for: shot(285, 200), among: [folded, unfolded]) === unfolded.image)
    // A landscape bezel never frames a portrait shot; a portrait one is turned for a landscape shot.
    #expect(ScreenshotFramer.bestBezel(for: shot(200, 400), among: [unfolded, portrait]) === portrait.image)
    #expect(ScreenshotFramer.bestBezel(for: shot(400, 200), among: [portrait]) === portrait.image)
    // A native landscape bezel of the same size wins the tie over a turned portrait one.
    let landscape = ScreenshotFramer.Bezel(image: bezel(screen: (400, 200)), screen: CGSize(width: 400, height: 200))
    #expect(ScreenshotFramer.bestBezel(for: shot(400, 200), among: [portrait, landscape]) === landscape.image)
  }

  /// The portrait bezel is turned counterclockwise as displayed (the Dynamic Island to the left),
  /// which CGContext's angle sign makes easy to get backwards.
  @Test func rotationIsCounterclockwiseAsDisplayed() throws {
    // 3×1, red at the left end.
    let context = CGContext(
      data: nil, width: 3, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    let rotated = try #require(ScreenshotFramer.rotated90CCW(context.makeImage()!))
    #expect(rotated.width == 1 && rotated.height == 3)
    // Read it back top row first: turned counterclockwise, the left end is at the bottom.
    var pixels = [UInt8](repeating: 0, count: 12)
    let reader = CGContext(
      data: &pixels, width: 1, height: 3, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    reader.draw(rotated, in: CGRect(x: 0, y: 0, width: 1, height: 3))
    #expect(pixels[8] == 255 && pixels[0] == 0)
  }
}
