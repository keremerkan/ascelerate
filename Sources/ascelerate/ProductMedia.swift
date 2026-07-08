import AppStoreAPI
import AppStoreConnect
import Foundation

// Shared drivers for the IAP/subscription media command trios (promotional images,
// App Review screenshots) and offer-code batch code viewing. The per-command structs
// in IAPCommand.swift / SubCommand.swift stay in place for argument parsing and help
// text; only the type-specific requests are passed in as closures.

/// Shared driver for `iap offer-code view-codes` / `sub offer-code view-codes`:
/// fetches the raw one-time-use code values via `fetch` and prints them or writes
/// them to `output`.
func runOfferCodeViewCodes(
  output: String?,
  fetch: () async throws -> String
) async throws {
  let raw = try await fetch()

  if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    print(yellow("⚠ No codes returned. Generation may still be in progress; retry in a few seconds."))
    return
  }

  if let output {
    let path = expandPath(confirmOutputPath(output, isDirectory: false))
    try raw.write(toFile: path, atomically: true, encoding: .utf8)
    let lineCount = raw.split(separator: "\n").count
    success("Wrote", "\(lineCount) code(s) to \(path).")
  } else {
    print(raw)
  }
}

/// Shared driver for `iap images list` / `sub images list`: prints the fetched
/// [ID, File, Size, State] rows as a table, or a no-images message when empty.
func runProductImagesList(
  productID: String,
  fetchRows: () async throws -> [[String]]
) async throws {
  let rows = try await fetchRows()

  if rows.isEmpty {
    print("No images uploaded for \(productID).")
    return
  }

  Table.print(headers: ["ID", "File", "Size", "State"], rows: rows)
}

/// Shared driver for the IAP/subscription image and review-screenshot uploads:
/// reads the file, prints the `summary` lines, confirms, runs the 3-step upload
/// protocol via `uploadAsset`, and prints the success message from `successDetail`.
func runProductAssetUpload(
  file: String,
  summary: (MediaFile) -> [String],
  reserve: (MediaFile) async throws -> (id: String, operations: [UploadOperation]),
  commit: (_ id: String, _ md5: String) async throws -> Void,
  successDetail: (_ id: String, _ media: MediaFile) -> String
) async throws {
  let media = try MediaFile(readingFrom: file)

  for line in summary(media) {
    print(line)
  }
  print()

  guard confirm("Upload? [y/N] ") else {
    cancelled()
    return
  }

  let assetID = try await uploadAsset(
    filePath: media.path,
    reserve: { try await reserve(media) },
    commit: commit
  )

  print()
  success("Uploaded", successDetail(assetID, media))
}

/// Shared driver for `iap images delete` / `sub images delete`: confirms, then
/// performs the type-specific delete.
func runProductImageDelete(
  imageID: String,
  delete: () async throws -> Void
) async throws {
  guard confirm("Delete image \(imageID)? [y/N] ") else {
    cancelled()
    return
  }

  try await delete()
  print()
  success("Deleted", "image \(imageID).")
}

/// Shared driver for `iap review-screenshot view` / `sub review-screenshot view`:
/// prints the screenshot details returned by `fetch`, treating DecodingError / 404
/// as "no screenshot uploaded".
func runReviewScreenshotView(
  productID: String,
  fetch: () async throws -> (id: String, fileName: String?, fileSizeText: String?, stateText: String?)
) async throws {
  do {
    let shot = try await fetch()
    print("Review Screenshot:")
    print("  ID:    \(shot.id)")
    print("  File:  \(shot.fileName ?? "—")")
    print("  Size:  \(shot.fileSizeText ?? "—")")
    print("  State: \(shot.stateText ?? "—")")
  } catch is DecodingError {
    print("No review screenshot uploaded for \(productID).")
  } catch let error as ResponseError {
    if case .requestFailure(_, let statusCode, _) = error, statusCode == 404 {
      print("No review screenshot uploaded for \(productID).")
    } else {
      throw error
    }
  }
}

/// Shared driver for `iap review-screenshot delete` / `sub review-screenshot delete`:
/// resolves the current screenshot's ID via `fetchID`, confirms, then deletes it.
func runReviewScreenshotDelete(
  productID: String,
  fetchID: () async throws -> String,
  delete: (_ screenshotID: String) async throws -> Void
) async throws {
  let screenshotID = try await fetchID()

  guard confirm("Delete review screenshot for \(productID)? [y/N] ") else {
    cancelled()
    return
  }

  try await delete(screenshotID)
  print()
  success("Deleted", "review screenshot.")
}
