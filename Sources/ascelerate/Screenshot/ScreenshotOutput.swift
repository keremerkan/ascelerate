import Foundation

/// Where the screenshot commands report progress. Normally it's readable text on stdout; with
/// `--json-events` stdout carries one JSON event per line for other tools, and the text moves to
/// stderr.
enum ScreenshotOutput {
  @TaskLocal static var emitsEvents = false

  /// A line of the readable progress.
  static func log(_ text: String = "") {
    if emitsEvents {
      FileHandle.standardError.write(Data((text + "\n").utf8))
    } else {
      print(text)
    }
  }

  static func emit(_ event: ScreenshotEvent) {
    guard emitsEvents else { return }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(event), let line = String(data: data, encoding: .utf8) else { return }
    print(line)
  }
}

/// A step of a screenshot run as `--json-events` reports it. `event` is one of:
/// - `start`: `scheme`, `devices`, `languages`, `outputDirectory` (absolute)
/// - `build`: `step` `started` or `finished`
/// - `language`: a language's turn begins (`language`, `index` from 1, `count`)
/// - `device`: `language`, `device` and `step`: `preparing`, `ready`, `testing`, `passed`, `failed`
///   (with `message`), `retrying` (`index` is the attempt) or `collected` (`count` screenshots)
/// - `finished`: `results` (one per language and device), `elapsed` seconds, `outputDirectory`
struct ScreenshotEvent: Encodable {
  struct Result: Encodable {
    let language: String
    let device: String
    let success: Bool
    let retried: Bool
    let error: String?
  }

  let event: String
  var step: String?
  var language: String?
  var device: String?
  var index: Int?
  var count: Int?
  var message: String?
  var scheme: String?
  var devices: [String]?
  var languages: [String]?
  var outputDirectory: String?
  var results: [Result]?
  var elapsed: Int?

  static func device(_ step: String, _ device: String, language: String, message: String? = nil, count: Int? = nil)
    -> ScreenshotEvent
  {
    ScreenshotEvent(event: "device", step: step, language: language, device: device, count: count, message: message)
  }
}
