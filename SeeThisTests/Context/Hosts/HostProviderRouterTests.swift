import CoreGraphics
import Carbon
import Foundation
import ApplicationServices
import AppKit
import SwiftUI
import Testing
@testable import SeeThis


struct HostProviderRouterTests {

    @Test @MainActor func hostProviderRouterSelectsOnlyKnownFrontmostHosts() {
        #expect(HostProviderRouter.host(for: "org.zotero.zotero") == .zotero)
        #expect(HostProviderRouter.host(for: "abnerworks.Typora") == .typora)
        #expect(HostProviderRouter.host(for: "com.apple.TextEdit") == .unsupported)
        #expect(HostProviderRouter.host(for: nil) == .unsupported)
    }

}
