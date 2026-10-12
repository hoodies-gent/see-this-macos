import Foundation

enum RuntimeEnvironment {
    // The unit tests run inside the app process; they must not register hotkeys or open windows.
    static let isRunningUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
