import ASCKit
import CryptoKit
import Foundation

/// A file to upload: its path, the name App Store Connect records, and its size.
public struct MediaFile: Sendable {
  public let path: String
  public let fileName: String
  public let fileSize: Int

  public init(path: String, fileName: String, fileSize: Int) {
    self.path = path
    self.fileName = fileName
    self.fileSize = fileSize
  }

  /// Reads a file's name and size from disk.
  public init(path: String) throws {
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    self.init(path: path, fileName: (path as NSString).lastPathComponent, fileSize: (attributes[.size] as? Int) ?? 0)
  }
}

public enum MediaUploadError: LocalizedError {
  case cannotReadFile(String)
  case invalidUploadOperation
  case chunkUploadFailed(Int)
  case noUploadOperations
  case unsupportedImage(String, accepted: [String])
  case unsupportedVideo(String, accepted: [String])
  case noMediaSets

  public var errorDescription: String? {
    switch self {
    case .noMediaSets:
      return "An in-app event's localization has no screenshot or preview sets."
    case .unsupportedImage(let image, let accepted):
      return "A \(image) image is not accepted here; use \(accepted.joined(separator: ", "))."
    case .unsupportedVideo(let video, let accepted):
      return "A video of \(video) is not accepted here; use \(accepted.joined(separator: "; or "))."
    case .cannotReadFile(let path):
      return "Cannot read file at '\(path)'."
    case .invalidUploadOperation:
      return "Upload operation missing required fields."
    case .chunkUploadFailed(let statusCode):
      return "Chunk upload failed with status \(statusCode)."
    case .noUploadOperations:
      return "No upload operations returned by the API."
    }
  }
}

// MARK: - Upload Progress

/// Receives one file upload's byte progress.
public protocol UploadProgressObserver: Sendable {
  /// Bytes sent so far of `total`; only ever grows.
  func progress(sent: Int64, total: Int64)
  /// The upload ended, done or failed.
  func finish()
  /// The sizes of the file's chunks, in upload order, as App Store Connect split it; before any
  /// progress. Lets an observer estimate progress within a chunk (it only hears of whole ones).
  func chunks(_ lengths: [Int64])
  /// Bytes handed to the network stack so far, only ever growing. They run ahead of the
  /// connection by its send buffers (megabytes on a slow uplink), so `progress` is the reliable
  /// figure; this one only shows that bytes are moving.
  func sending(sent: Int64, total: Int64)
}

extension UploadProgressObserver {
  public func chunks(_ lengths: [Int64]) {}
  public func sending(sent: Int64, total: Int64) {}
}

public enum UploadOptions {
  /// How many of a file's chunks upload at once. One (the default) keeps the connection's bandwidth
  /// for one request at a time, so other traffic keeps moving and progress advances chunk by chunk;
  /// several help a fast connection with a long round trip to Apple's storage.
  @TaskLocal public static var parallelChunks = 1
}

public enum UploadProgress {
  /// Called with each file upload's total bytes before its chunks go out; the observer it returns
  /// follows that upload. Nil (the default) reports nothing.
  @TaskLocal public static var observe: (@Sendable (_ totalBytes: Int64) -> (any UploadProgressObserver)?)?
}

/// Sums the bytes of a file's chunks as Apple acknowledges them (`progress`), and as URLSession
/// hands them to the network (`sending`), for its observer. The handed-off bytes reached 100% while
/// megabytes were still going out (seen live: 100% after 14 s, the last chunk acknowledged after
/// 53 s), so only acknowledged chunks count as progress.
private final class ChunkProgress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  private let lock = NSLock()
  private let observer: any UploadProgressObserver
  private let total: Int64
  /// Bytes of the chunks Apple accepted.
  private var finished: Int64 = 0
  /// Bytes handed off so far by each chunk in flight.
  private var inFlight: [Int: Int64] = [:]
  private var reportedSending: Int64 = -1

  init(observer: any UploadProgressObserver, totalBytes: Int64) {
    self.observer = observer
    total = totalBytes
  }

  /// Counts a chunk Apple accepted.
  func chunkFinished(length: Int64) {
    lock.withLock {
      finished += length
      observer.progress(sent: min(finished, total), total: total)
    }
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
    totalBytesSent: Int64, totalBytesExpectedToSend: Int64
  ) {
    lock.withLock {
      inFlight[task.taskIdentifier] = totalBytesSent
      let sent = min(finished + inFlight.values.reduce(0, +), total)
      // Only forward: a finished chunk leaves `inFlight` around when it's counted.
      guard sent > reportedSending else { return }
      reportedSending = sent
      observer.sending(sent: sent, total: total)
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
    _ = lock.withLock { inFlight.removeValue(forKey: task.taskIdentifier) }
  }
}

// MARK: - Upload Helpers

/// An upload operation's fields as `uploadChunks` reads them.
public protocol UploadOperationDescribing {
  var url: String? { get }
  var method: String? { get }
  var offset: Int? { get }
  var length: Int? { get }
  var headers: [(name: String, value: String)] { get }
}

extension Components.Schemas.UploadOperation: UploadOperationDescribing {
  public var headers: [(name: String, value: String)] {
    (requestHeaders ?? []).compactMap { header in header.name.flatMap { name in header.value.map { (name, $0) } } }
  }
}

/// One upload operation's request, ready to send from any task.
private struct UploadChunk: Sendable {
  let request: URLRequest
  let offset: Int
  let length: Int
}

/// PUTs the file's chunks to their presigned URLs, `UploadOptions.parallelChunks` at a time,
/// reporting the acknowledged bytes to the `UploadProgress.observe` observer.
public func uploadChunks<Operation: UploadOperationDescribing>(filePath: String, operations: [Operation]) async throws {
  guard FileManager.default.isReadableFile(atPath: filePath) else {
    throw MediaUploadError.cannotReadFile(filePath)
  }
  let chunks = try operations.map { operation in
    guard let urlString = operation.url,
      let url = URL(string: urlString),
      let method = operation.method,
      let offset = operation.offset,
      let length = operation.length
    else {
      throw MediaUploadError.invalidUploadOperation
    }
    var request = URLRequest(url: url)
    request.httpMethod = method
    for header in operation.headers {
      request.setValue(header.value, forHTTPHeaderField: header.name)
    }
    return UploadChunk(request: request, offset: offset, length: length)
  }

  let total = chunks.reduce(0) { $0 + Int64($1.length) }
  let observer = UploadProgress.observe?(total)
  defer { observer?.finish() }
  observer?.chunks(chunks.map { Int64($0.length) })
  let progress = observer.map { ChunkProgress(observer: $0, totalBytes: total) }

  _ = try await boundedConcurrentMap(chunks, maxConcurrent: max(1, UploadOptions.parallelChunks)) { chunk in
    try await upload(chunk, from: filePath, progress: progress)
  }
}

private func upload(_ chunk: UploadChunk, from filePath: String, progress: ChunkProgress?) async throws {
  // Each chunk reads its own slice: a shared handle's seek position would race.
  guard let fileHandle = FileHandle(forReadingAtPath: filePath) else {
    throw MediaUploadError.cannotReadFile(filePath)
  }
  try fileHandle.seek(toOffset: UInt64(chunk.offset))
  let chunkData = fileHandle.readData(ofLength: chunk.length)
  try? fileHandle.close()

  // The storage host rate-limits bursts (HTTP 429 seen live after ~180 sequential uploads);
  // retry 429/5xx with backoff, honoring Retry-After, and dropped or timed-out connections.
  // A chunk PUT to its presigned URL is safe to repeat.
  var delays: [Double] = [2, 5, 15, 30]
  while true {
    let response: URLResponse
    do {
      (_, response) = try await URLSession.shared.upload(for: chunk.request, from: chunkData, delegate: progress)
    } catch where isTransientError(error) && !delays.isEmpty {
      try await Task.sleep(for: .seconds(delays.removeFirst()))
      continue
    }
    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
    if (200...299).contains(statusCode) {
      progress?.chunkFinished(length: Int64(chunk.length))
      return
    }
    guard statusCode == 429 || (500...599).contains(statusCode), !delays.isEmpty else {
      throw MediaUploadError.chunkUploadFailed(statusCode)
    }
    let delay = delays.removeFirst()
    let retryAfter = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
    try await Task.sleep(for: .seconds(min(retryAfter ?? delay, 60)))
  }
}

public func md5Hex(filePath: String) throws -> String {
  guard let fileHandle = FileHandle(forReadingAtPath: filePath) else {
    throw MediaUploadError.cannotReadFile(filePath)
  }
  defer { try? fileHandle.close() }

  var md5 = Insecure.MD5()
  let bufferSize = 1024 * 1024

  while true {
    let data = fileHandle.readData(ofLength: bufferSize)
    if data.isEmpty { break }
    md5.update(data: data)
  }

  let digest = md5.finalize()
  return digest.map { String(format: "%02x", $0) }.joined()
}

/// Runs the App Store Connect 3-step asset upload protocol shared by app screenshots/previews,
/// IAP/subscription promotional images, and App Review screenshots:
/// reserve → upload chunks → commit with checksum.
///
/// - Parameters:
///   - reserve: performs the create POST; returns the new asset's ID and its upload operations.
///   - commit: performs the PATCH marking the asset uploaded, given the ID and computed MD5 checksum.
/// - Returns: the new asset's ID.
public func uploadAsset<Operation: UploadOperationDescribing>(
  filePath: String,
  reserve: () async throws -> (id: String, operations: [Operation]),
  commit: (_ id: String, _ md5: String) async throws -> Void
) async throws -> String {
  let (id, operations) = try await reserve()
  guard !operations.isEmpty else {
    throw MediaUploadError.noUploadOperations
  }
  try await uploadChunks(filePath: filePath, operations: operations)
  let md5 = try md5Hex(filePath: filePath)
  // The commit PATCH only marks the asset uploaded, so it is safe to repeat.
  try await withTransientRetry { try await commit(id, md5) }
  return id
}

public func mediaMimeType(for fileName: String) -> String {
  let ext = (fileName as NSString).pathExtension.lowercased()
  switch ext {
  case "mp4": return "video/mp4"
  case "mov": return "video/quicktime"
  default: return "application/octet-stream"
  }
}
