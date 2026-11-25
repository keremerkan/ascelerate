import Foundation
import Testing
@testable import AscelerateCore

/// File names from Apple, as files saved under a folder.
@Suite struct MediaDownloadTests {
  @Test func safeFileNames() {
    #expect(MediaDownload.safeFileName("01_home.png", fallback: "x") == "01_home.png")
    // A path names no folder: slashes become underscores.
    #expect(MediaDownload.safeFileName("../etc/passwd", fallback: "x") == ".._etc_passwd")
    #expect(MediaDownload.safeFileName("/abs/name.zip", fallback: "x") == "_abs_name.zip")
    // Nothing usable falls back.
    for bad in [nil, "", " ", ".", ".."] as [String?] {
      #expect(MediaDownload.safeFileName(bad, fallback: "artifact-1") == "artifact-1")
    }
  }

  @Test func clearFileRemovesAFileButNeverAFolder() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ascelerate-clear-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("a.txt")
    try Data("x".utf8).write(to: file)
    try MediaDownload.clearFile(at: file)
    #expect(!FileManager.default.fileExists(atPath: file.path))
    let inner = folder.appendingPathComponent("inner")
    try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
    #expect(throws: MediaDownload.FolderInTheWay.self) { try MediaDownload.clearFile(at: inner) }
    #expect(FileManager.default.fileExists(atPath: inner.path))
  }
}
