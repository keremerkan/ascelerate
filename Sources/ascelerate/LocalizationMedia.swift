import ArgumentParser
import ASCKit
import AscelerateCore
import Foundation

/// One file at a time for a localization outside `apps media`'s folder flow: a custom product page
/// localization (`product-pages media`) or a product page optimization treatment localization
/// (`experiments media`). Screenshots and previews go to classic sets; PRODUCT_PAGE_HEADER,
/// APP_STORE_SEARCH_RESULTS and APP_IPHONE_DUO go through the asset library.
extension LocalizationMedia {
  /// One screenshot, preview or library placement of a localization, with raw values: `kind` is
  /// `screenshot`, `preview`, `image` or `video`, `type` the display or preview type (raw, as the
  /// options take it) or the slot, `state` Apple's (`COMPLETE`, `ACTIVE`, …).
  struct Item: Encodable {
    let id: String
    let kind: String
    let type: String?
    let state: String?
  }

  /// Every screenshot, preview and library placement of the localization.
  static func items(on owner: Owner, client: ASCClient) async throws -> [Item] {
    var items: [Item] = []
    // Each kind's sets come with their media in one request; the API's mirrors of library slots
    // (iPhone Duo) are left out, their placements listed below.
    for (set, screenshots) in try await screenshotSetsWithScreenshots(on: owner, client: client)
    where AssetLibrary.slots[set.attributes?.screenshotDisplayType ?? ""] == nil {
      for s in screenshots {
        items.append(Item(id: s.id, kind: "screenshot", type: set.attributes?.screenshotDisplayType, state: s.attributes?.assetDeliveryState?.state))
      }
    }
    for (set, previews) in try await previewSetsWithPreviews(on: owner, client: client)
    where AssetLibrary.slots["APP_\(set.attributes?.previewType ?? "")"] == nil {
      for p in previews {
        items.append(Item(id: p.id, kind: "preview", type: set.attributes?.previewType, state: p.attributes?.assetDeliveryState?.state))
      }
    }
    // Asset library placements: header, search results, iPhone Duo.
    for (slot, placement) in try await AssetLibrary.slotPlacements(on: owner, client: client) {
      items.append(Item(
        id: placement.id, kind: placement.attributes?.mediaType == "VIDEO" ? "video" : "image", type: slot,
        state: placement.attributes?.state))
    }
    return items
  }

  /// `[locale, kind, type, state, media ID]` table rows for every screenshot, preview and library
  /// placement, from `items`.
  static func rows(locale: String, on owner: Owner, client: ASCClient) async throws -> [[String]] {
    try await items(on: owner, client: client).map { item in
      [locale, item.kind.prefix(1).uppercased() + item.kind.dropFirst(), item.type ?? "—", item.state.map { formatState($0) } ?? "—", item.id]
    }
  }

  static let uploadDiscussion = """
    --display-type or --preview-type can also name an asset library slot:
    PRODUCT_PAGE_HEADER or APP_STORE_SEARCH_RESULTS (one image or video, replacing
    the current one) or APP_IPHONE_DUO (a screenshot or app preview, added after the
    existing ones). Sizes are checked against Apple's specs before uploading.
    """

  /// Uploads one screenshot (`displayType`) or preview (`previewType`), or places a library slot
  /// image/video. `context` is the summary's leading lines (e.g. `("Page", name)`). Without an
  /// `owner`, `createOwner` makes the localization once the user has confirmed.
  static func upload(
    file: String, displayType: String?, previewType: String?, previewFrame: String?,
    appID: String, context: [(String, String)], client: ASCClient,
    owner existing: Owner?, createOwner: () async throws -> Owner? = { throw ValidationError("No localization to upload to.") }
  ) async throws {
    try checkPreviewFrame(previewFrame)
    let media = try MediaFile(readingFrom: file)
    let ext = (media.fileName as NSString).pathExtension.lowercased()
    let isImage = imageExtensions.contains(ext)
    let isVideo = videoExtensions.contains(ext)
    let slotName = [displayType, previewType].compactMap { $0?.uppercased() }.first { AssetLibrary.slots[$0] != nil }
    let slot = slotName.flatMap { AssetLibrary.slots[$0] }

    if let slot {
      guard !isVideo || slot.videoPlacementType != nil else { throw ValidationError("\(slotName ?? "") takes images only.") }
    } else {
      guard isImage || isVideo else {
        throw ValidationError("Unsupported file type '.\(ext)'. Use png/jpg for screenshots or mp4/mov for previews.")
      }
      if isImage && displayType == nil { throw ValidationError("--display-type is required for screenshots (e.g. APP_IPHONE_67).") }
      if isVideo && previewType == nil { throw ValidationError("--preview-type is required for app previews (e.g. APP_IPHONE_67).") }
    }
    let display: ASCEnum.ScreenshotDisplayType? = try slot == nil && isImage ? parseEnum(displayType ?? "", name: "display-type") : nil
    // Both forms: the display type's name (APP_IPHONE_67, as the folders and the docs have it) or
    // the preview type's own (IPHONE_67).
    let preview: ASCEnum.PreviewType?
    if slot == nil && isVideo {
      let raw = (previewType ?? "").uppercased()
      if let fromDisplay = AssetLibrary.previewType(of: raw) {
        preview = fromDisplay
      } else {
        preview = try parseEnum(raw, name: "preview-type") as ASCEnum.PreviewType
      }
    } else {
      preview = nil
    }

    let current = if let slot, slot.isSingle, let existing {
      try await AssetLibrary.placements(on: existing, type: slot.placementType, group: slot.group, client: client).map(\.id)
    } else { [String]() }

    let what = slot != nil ? (isVideo ? "video" : "image") : (isImage ? "screenshot" : "app preview")
    print(slot != nil ? "Upload \(what) to the asset library:" : "Upload \(what):")
    let width = (context.map(\.0) + ["Type", "File"]).map(\.count).max() ?? 0
    func line(_ label: String, _ value: String) { print("  \((label + ":").padding(toLength: width + 2, withPad: " ", startingAt: 0))\(value)") }
    for (label, value) in context { line(label, value) }
    line(slot != nil ? "Slot" : "Type", (slotName ?? (display?.rawValue ?? preview?.rawValue ?? "—")) + (current.isEmpty ? "" : " (replaces the current one)"))
    line("File", "\(media.fileName) (\(formatBytes(media.fileSize)))")
    print()
    guard confirm("Upload? [y/N] ") else {
      cancelled()
      return
    }
    var owner = existing
    if owner == nil { owner = try await createOwner() }
    // Nil under dry run: the language wasn't created, so there's nothing to upload into (a
    // placeholder ID would go into real reads and end in a 404).
    guard let owner else { return print("Dry run: the language would be created first; the upload goes into it.") }

    if let slot {
      let libraryID = try await AssetLibrary.libraryID(appID: appID, client: client)
      let placementID = try await AssetLibrary.uploadAndPlace(media, slot: slot, on: owner, libraryID: libraryID, replacing: current, client: client)
      print()
      success("Uploaded", "\(what) (placement id: \(placementID)).")
      return
    }

    let mediaID: String
    if let display {
      var setID = try await screenshotSets(on: owner, client: client).first { $0.attributes?.screenshotDisplayType == display.rawValue }?.id
      if setID == nil { setID = try await ClassicMedia.createScreenshotSet(display, owner: owner, client: client) }
      mediaID = try await ClassicMedia.uploadScreenshot(media, setID: setID ?? "", client: client)
    } else if let preview {
      var setID = try await previewSets(on: owner, client: client).first { $0.attributes?.previewType == preview.rawValue }?.id
      if setID == nil { setID = try await ClassicMedia.createPreviewSet(preview, owner: owner, client: client) }
      mediaID = try await ClassicMedia.uploadPreview(media, setID: setID ?? "", previewFrame: previewFrame, client: client)
    } else {
      return
    }
    print()
    success("Uploaded", "\(what) (id: \(mediaID)).")
  }

  /// Deletes a screenshot, preview or library placement found on one of `owners`.
  static func delete(mediaID: String, among owners: [Owner], client: ASCClient) async throws {
    // Each owner's media in three requests (`items`), instead of one per set.
    for owner in owners {
      guard let match = try await items(on: owner, client: client).first(where: { $0.id == mediaID }) else { continue }
      switch match.kind {
        case "screenshot":
          guard confirm("Delete this screenshot? [y/N] ") else { return cancelled() }
          try await ClassicMedia.deleteScreenshot(mediaID, client: client)
          print()
          return success("Deleted", "screenshot \(mediaID).")
        case "preview":
          guard confirm("Delete this preview? [y/N] ") else { return cancelled() }
          try await ClassicMedia.deletePreview(mediaID, client: client)
          print()
          return success("Deleted", "preview \(mediaID).")
        default:
          // An asset library placement: removing it also deletes its image or video from the
          // library when nothing else uses it.
          let slot = match.type ?? match.kind
          guard confirm("Remove this \(slot) placement? [y/N] ") else { return cancelled() }
          guard let deleted = try await unlessDryRunStopped({ try await AssetLibrary.removePlacement(id: mediaID, client: client) }) else {
            return print("Dry run: the \(slot) placement \(mediaID) wasn't removed.")
          }
          print()
          return success("Removed", "\(slot) placement \(mediaID)\(deleted ? " and its unused library file" : "").")
      }
    }
    throw ValidationError("Media '\(mediaID)' not found.")
  }
}
