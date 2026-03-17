import Foundation

enum ScreenshotShell {
    @discardableResult
    static func run(_ command: String, arguments: [String] = []) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        trackProcess(process)
        setupSignalHandler()
        process.waitUntilExit()
        untrackProcess(process)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw ScreenshotShellError.nonZeroExit(process.terminationStatus, output)
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
        trackProcess(process)
        setupSignalHandler()
        process.waitUntilExit()
        untrackProcess(process)

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
        trackProcess(process)
        setupSignalHandler()
        process.waitUntilExit()
        untrackProcess(process)

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
