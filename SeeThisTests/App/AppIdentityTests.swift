import Testing
@testable import SeeThis

struct AppIdentityTests {
    @Test func exposesTheSeeThisPublicIdentity() {
        #expect(AppIdentity.displayName == "SeeThis")
        #expect(AppIdentity.bundleIdentifier == "io.github.hoodies-gent.seethis")
        #expect(AppIdentity.keychainService == "io.github.hoodies-gent.seethis")
        #expect(AppIdentity.tagline == "Select it. Ask AI. Keep reading.")
        #expect(AppIdentity.releaseVersion == "0.1.1")
    }

    @Test func deeplCredentialUsesTheSeeThisKeychainService() {
        #expect(DeepLTranslationCapability.credentialKey.service == AppIdentity.keychainService)
        #expect(DeepLTranslationCapability.credentialKey.account == "deepl.api-key")
    }
}
