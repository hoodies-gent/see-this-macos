import Foundation

nonisolated enum AppIdentity {
    static let displayName = "SeeThis"
    static let releaseVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    static let bundleIdentifier = "io.github.hoodies-gent.seethis"
    static let keychainService = bundleIdentifier
    static let tagline = "Select it. Ask AI. Keep reading."
}
