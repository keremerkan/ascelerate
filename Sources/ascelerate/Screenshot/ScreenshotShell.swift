import Foundation

enum ScreenshotShell {
    @discardableResult
    static func run(_ command: String, arguments: [String] = []) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        // stderr apart from stdout: one warning line in front of simctl's JSON made every
        // simulator "not found". It goes to a file (no second pipe to drain while reading this one)
        // and into the error when the command fails.
        let errorFile = FileManager.default.temporaryDirectory.appendingPathComponent("ascelerate-stderr-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: errorFile.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: errorFile) }
        process.standardError = try FileHandle(forWritingTo: errorFile)

        try process.run()
        // Reads the pipe before waiting (`simctl list devices -j` alone exceeds its buffer).
        let data = waitForwardingInterrupts(process, reading: pipe)

        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            let errors = (try? String(contentsOf: errorFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ScreenshotShellError.nonZeroExit(process.terminationStatus, [errors, output].filter { !$0.isEmpty }.joined(separator: "\n"))
        }

        return output
    }

    static func stream(_ command: String, arguments: [String] = []) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        try process.run()
        waitForwardingInterrupts(process)

        return process.terminationStatus
    }

    static func runToLog(_ command: String, arguments: [String] = [], logFile: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        FileManager.default.createFile(atPath: logFile.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: logFile)

        process.standardOutput = fileHandle
        process.standardError = fileHandle

        try process.run()
        waitForwardingInterrupts(process)

        try fileHandle.close()

        return process.terminationStatus
    }

    static func tail(_ fileURL: URL, lines: Int = 20) -> String {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return "" }
        let allLines = content.components(separatedBy: .newlines)
        let lastLines = allLines.suffix(lines)
        return lastLines.joined(separator: "\n")
    }
}

enum ScreenshotShellError: Error, CustomStringConvertible {
    case nonZeroExit(Int32, String)

    var description: String {
        switch self {
        case .nonZeroExit(let code, let output):
            "Command failed with exit code \(code): \(output)"
        }
    }
}
