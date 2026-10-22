import ArgumentParser
import CryptoKit
import Foundation

/// Updates a copy installed from a GitHub release (not Homebrew's) to the latest release: the
/// download must match the digest GitHub publishes for it and be signed with ascelerate's
/// Developer ID before it replaces this binary.
struct UpdateCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "update",
    abstract: "Update ascelerate to the latest release from GitHub.",
    discussion: """
      For a copy installed from a GitHub release (Apple silicon). The download is checked against \
      the SHA-256 digest GitHub publishes and must be signed with ascelerate's Developer ID before it \
      replaces this binary. A copy installed with Homebrew updates with 'brew upgrade ascelerate'. \
      Updating a copy in /usr/local/bin needs 'sudo ascelerate update'.
      """
  )

  @Flag(name: .long, help: "Only say whether a newer release exists.")
  var check = false

  @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
  var yes = false

  static let repository = "keremerkan/ascelerate"
  static let assetName = "ascelerate-macos-arm64.tar.gz"
  /// The code requirement a release binary meets: Developer ID Application, team GH4CGS3B5H.
  static let requirement = #"anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "GH4CGS3B5H""#

  enum UpdateError: LocalizedError {
    case homebrew
    case noAsset(String)
    case digestMismatch
    case unsigned(String)
    case notWritable(String)
    case extraction(String)

    var errorDescription: String? {
      switch self {
        case .homebrew:
          "This copy was installed with Homebrew. Update it with 'brew upgrade ascelerate'."
        case .noAsset(let tag):
          "Release \(tag) has no \(UpdateCommand.assetName)."
        case .digestMismatch:
          "The download doesn't match the SHA-256 digest GitHub published for it. Nothing was changed."
        case .unsigned(let detail):
          "The downloaded binary isn't signed with ascelerate's Developer ID, so it wasn't installed.\n\(detail)"
        case .notWritable(let folder):
          "Can't write to \(folder). Run 'sudo ascelerate update'."
        case .extraction(let detail):
          "Couldn't unpack the download: \(detail)"
      }
    }
  }

  private struct Release: Decodable {
    struct Asset: Decodable {
      let name: String
      let browserDownloadUrl: URL
      /// "sha256:<hex>", on assets uploaded since mid 2025.
      let digest: String?
    }
    let tagName: String
    let assets: [Asset]
  }

  func run() async throws {
    if yes { autoConfirm = true }
    let binary = Bundle.main.executableURL!.resolvingSymlinksInPath()
    if binary.path.contains("/Cellar/") || binary.path.hasPrefix("/opt/homebrew/") {
      throw UpdateError.homebrew
    }

    let release = try await Self.latestRelease()
    let latest = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
    guard isVersionOlder(Ascelerate.appVersion, than: latest) else {
      print("ascelerate \(Ascelerate.appVersion) is the latest release.")
      return
    }
    if check {
      print("ascelerate \(latest) is available (this is \(Ascelerate.appVersion)). Run 'ascelerate update' to install it.")
      return
    }
    guard let asset = release.assets.first(where: { $0.name == Self.assetName }) else {
      throw UpdateError.noAsset(release.tagName)
    }
    let folder = binary.deletingLastPathComponent()
    guard FileManager.default.isWritableFile(atPath: folder.path) else {
      throw UpdateError.notWritable(folder.path)
    }

    print("Update ascelerate \(Ascelerate.appVersion) → \(latest) at \(binary.path)?")
    guard confirm("Download and install it? [y/N] ") else {
      cancelled()
      return
    }

    let work = FileManager.default.temporaryDirectory.appendingPathComponent("ascelerate-update-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: work) }

    print("Downloading \(asset.name)...")
    let (download, _) = try await URLSession.shared.download(from: asset.browserDownloadUrl)
    let archive = work.appendingPathComponent(asset.name)
    try FileManager.default.moveItem(at: download, to: archive)
    if let digest = asset.digest, digest.hasPrefix("sha256:") {
      let actual = SHA256.hash(data: try Data(contentsOf: archive)).map { String(format: "%02x", $0) }.joined()
      guard actual == digest.dropFirst("sha256:".count).lowercased() else { throw UpdateError.digestMismatch }
    }

    let unpacked = work.appendingPathComponent("ascelerate")
    let tar = Self.runTool("/usr/bin/tar", ["-xzf", archive.path, "-C", work.path])
    guard tar.status == 0, FileManager.default.fileExists(atPath: unpacked.path) else {
      throw UpdateError.extraction(tar.output)
    }
    let verify = Self.runTool("/usr/bin/codesign", ["--verify", "--strict", "-R=\(Self.requirement)", unpacked.path])
    guard verify.status == 0 else { throw UpdateError.unsigned(verify.output) }

    // Next to the binary, then renamed over it: the swap is atomic, and a failure leaves the old one.
    let staged = folder.appendingPathComponent(".ascelerate-update")
    try? FileManager.default.removeItem(at: staged)
    try FileManager.default.copyItem(at: unpacked, to: staged)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staged.path)
    guard rename(staged.path, binary.path) == 0 else {
      let reason = String(cString: strerror(errno))
      try? FileManager.default.removeItem(at: staged)
      throw ValidationError("Couldn't replace \(binary.path): \(reason)")
    }
    success("Updated", "ascelerate to \(latest).")
  }

  private static func latestRelease() async throws -> Release {
    var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    let (data, response) = try await URLSession.shared.data(for: request)
    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
      throw ValidationError("GitHub answered HTTP \(http.statusCode) for the latest release.")
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(Release.self, from: data)
  }

  /// Runs a system tool, returning its exit status and its output (standard error included).
  private static func runTool(_ path: String, _ arguments: [String]) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
      try process.run()
    } catch {
      return (-1, error.localizedDescription)
    }
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    return (process.terminationStatus, output.trimmingCharacters(in: .whitespacesAndNewlines))
  }
}
