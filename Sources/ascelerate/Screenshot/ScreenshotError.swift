import Foundation

enum ScreenshotError: Error, CustomStringConvertible {
    case simulatorNotFound(String)
    case xcodebuildFailed(Int32)
    case configNotFound(String)
    case noProjectSpecified
    case derivedDataNotFound(String)
    case xctestrunNotFound(String)

    var description: String {
        switch self {
        case .simulatorNotFound(let name):
            "Simulator '\(name)' not found. Run 'xcrun simctl list devices available' to see available devices."
        case .xcodebuildFailed(let code):
            "xcodebuild failed with exit code \(code)"
        case .configNotFound(let path):
            "Config file not found at '\(path)'\nRun 'ascelerate screenshot init' to create one."
        case .noProjectSpecified:
            "No 'project' or 'workspace' specified in config"
        case .derivedDataNotFound(let name):
            "Could not find derived data for '\(name)' in ~/Library/Developer/Xcode/DerivedData/. Build the project in Xcode first, or set 'derivedDataPath' in config."
        case .xctestrunNotFound(let path):
            "No .xctestrun file found in \(path)/Build/Products/. Build for Testing (Cmd+Shift+U) in Xcode first."
        }
    }
}
