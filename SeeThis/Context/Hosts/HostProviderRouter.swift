import AppKit

enum FrontmostHost: Equatable {
    case zotero
    case typora
    case unsupported

    var bundleIdentifier: String? {
        switch self {
        case .zotero: HostBundleIdentifier.zotero
        case .typora: HostBundleIdentifier.typora
        case .unsupported: nil
        }
    }
}

enum HostBundleIdentifier {
    static let zotero = "org.zotero.zotero"
    static let typora = "abnerworks.Typora"
}

enum HostProviderRouter {
    static func frontmostHost() -> FrontmostHost {
        host(for: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    static func host(for bundleIdentifier: String?) -> FrontmostHost {
        switch bundleIdentifier {
        case HostBundleIdentifier.zotero:
            return .zotero
        case HostBundleIdentifier.typora:
            return .typora
        default:
            return .unsupported
        }
    }
}
