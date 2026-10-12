import Testing
@testable import SeeThis

struct CapabilityRegistryTests {

    @Test func resolvesOnlyCapabilitiesRegisteredByTheApp() async throws {
        let capability = RecordingCapability(id: "test.translate")
        let registry = try CapabilityRegistry(capabilities: [capability])

        let resolved = try registry.resolve("test.translate").get()
        let result = await resolved.invoke(
            .translate(
                TranslateCapabilityInput(
                    selection: "Synthetic selection.",
                    sourceLanguage: nil,
                    targetLanguage: "DE"
                )
            )
        )

        #expect(registry.registeredIDs == ["test.translate"])
        #expect(result == .success(.text("Translated text.")))
        #expect(
            await capability.inputs() == [
                .translate(
                    TranslateCapabilityInput(
                        selection: "Synthetic selection.",
                        sourceLanguage: nil,
                        targetLanguage: "DE"
                    )
                )
            ]
        )
    }

    @Test func rejectsUnknownCapabilityWithoutInvokingAProvider() async throws {
        let capability = RecordingCapability(id: "test.translate")
        let registry = try CapabilityRegistry(capabilities: [capability])

        let result = registry.resolve("unknown.capability")

        guard case let .failure(error) = result else {
            Issue.record("Expected an unknown capability to be rejected")
            return
        }
        #expect(error == .unknownCapability("unknown.capability"))
        #expect(await capability.inputs().isEmpty)
    }

    @Test func rejectsDuplicateCapabilityRegistrations() {
        #expect(throws: CapabilityRegistryError.duplicateCapability("test.translate")) {
            try CapabilityRegistry(
                capabilities: [
                    RecordingCapability(id: "test.translate"),
                    RecordingCapability(id: "test.translate")
                ]
            )
        }
    }

    @Test func capabilityErrorsRemainTypedAndContentFree() async throws {
        let capability = RecordingCapability(
            id: "test.translate",
            result: .failure(.providerRejected(statusCode: 429))
        )
        let registry = try CapabilityRegistry(capabilities: [capability])
        let resolved = try registry.resolve("test.translate").get()

        let result = await resolved.invoke(
            .translate(
                TranslateCapabilityInput(
                    selection: "Sensitive synthetic selection.",
                    sourceLanguage: "EN",
                    targetLanguage: "JA"
                )
            )
        )

        #expect(result == .failure(.providerRejected(statusCode: 429)))
        #expect(String(describing: result).contains("Sensitive synthetic selection.") == false)
    }
}

private actor RecordingCapability: Capability {
    nonisolated let descriptor: CapabilityDescriptor

    private let result: Result<CapabilityOutput, CapabilityError>
    private var recordedInputs: [CapabilityInput] = []

    init(
        id: String,
        result: Result<CapabilityOutput, CapabilityError> = .success(.text("Translated text."))
    ) {
        descriptor = CapabilityDescriptor(
            id: id,
            requiredPermissions: [
                .network(
                    host: "api-free.deepl.com",
                    egress: ["selection", "sourceLanguage", "targetLanguage"]
                )
            ]
        )
        self.result = result
    }

    func invoke(_ input: CapabilityInput) async -> Result<CapabilityOutput, CapabilityError> {
        recordedInputs.append(input)
        return result
    }

    func inputs() -> [CapabilityInput] {
        recordedInputs
    }
}
