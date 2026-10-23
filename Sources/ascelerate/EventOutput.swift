import Foundation

/// Where a command that other tools can follow reports progress (`screenshot`, `builds archive`,
/// `builds upload`). Normally it's readable text on stdout; with `--json-events` stdout carries one
/// JSON event per line for other tools, and the text moves to stderr.
enum EventOutput {
  @TaskLocal static var emitsEvents = false

  /// A line of the readable progress.
  static func log(_ text: String = "") {
    if emitsEvents {
      FileHandle.standardError.write(Data((text + "\n").utf8))
    } else {
      print(text)
    }
  }

  // One overload per event type, so call sites can write `.device(…)`.
  static func emit(_ event: ScreenshotEvent) { write(event) }
  static func emit(_ event: BuildEvent) { write(event) }

  private static func write(_ event: some Encodable) {
    guard emitsEvents else { return }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(event), let line = String(data: data, encoding: .utf8) else { return }
    print(line)
  }
}
