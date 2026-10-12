import Foundation
import Testing
@testable import SeeThis

struct ActionManifestValidatorTests {

    private let validator = ActionManifestValidator(
        runtimeVersion: SemanticVersion(1, 0, 0),
        knownCapabilityIDs: ["test.dictionary"]
    )

    @Test func rejectsModelPromptAsAForbiddenPackageStrategy() throws {
        let result = validator.validate(data: try manifestData { manifest in
            manifest["execution"] = [
                "strategy": "modelPrompt",
                "prompt": "Explain the selection clearly."
            ]
            manifest["permissions"] = [["kind": "localModel"]]
            manifest["budget"] = ["maxModelCalls": 1, "maxCapabilityCalls": 0]
        })

        #expect(result.manifest == nil)
        #expect(
            result.diagnostics == [
                ActionManifestDiagnostic(
                    code: .forbiddenStrategy,
                    message: "Execution strategy 'modelPrompt' is reserved for internal Lens actions."
                )
            ]
        )
    }

    @Test func parsesValidSingleCapabilityManifest() throws {
        let result = validator.validate(data: try manifestData())

        #expect(result.diagnostics.isEmpty)
        #expect(result.manifest?.schemaVersion == 1)
        #expect(result.manifest?.id == "community.explain")
        #expect(result.manifest?.version == SemanticVersion(1, 2, 0))
        #expect(result.manifest?.display.name == "Explain clearly")
        #expect(result.manifest?.display.allowsFollowUp == true)
        #expect(result.manifest?.input.selection == .required)
        #expect(
            result.manifest?.execution
                == .singleCapability(capabilityID: "test.dictionary")
        )
        #expect(result.manifest?.permissions == [.localDictionary])
        #expect(result.manifest?.budget == ActionBudget(maxModelCalls: 0, maxCapabilityCalls: 1))
        #expect(result.manifest?.output == ActionOutputContract(kind: .text, format: .markdown))
    }

    @Test func parsesAllAllowedExecutionStrategies() throws {
        let cases: [(
            name: String,
            execution: [String: Any],
            permissions: [[String: Any]],
            budget: [String: Int],
            expected: ActionPackageExecutionStrategy
        )] = [
            (
                "single capability",
                ["strategy": "singleCapability", "capability": "test.dictionary"],
                [["kind": "localDictionary"]],
                ["maxModelCalls": 0, "maxCapabilityCalls": 1],
                .singleCapability(capabilityID: "test.dictionary")
            ),
            (
                "bounded agent",
                [
                    "strategy": "boundedAgent",
                    "prompt": "Use the declared capability only when needed.",
                    "capabilities": ["test.dictionary"]
                ],
                [["kind": "localModel"], ["kind": "localDictionary"]],
                ["maxModelCalls": 2, "maxCapabilityCalls": 1],
                .boundedAgent(
                    prompt: "Use the declared capability only when needed.",
                    capabilityIDs: ["test.dictionary"]
                )
            )
        ]

        for testCase in cases {
            let result = validator.validate(data: try manifestData { manifest in
                manifest["execution"] = testCase.execution
                manifest["permissions"] = testCase.permissions
                manifest["budget"] = testCase.budget
            })

            #expect(
                result.diagnostics.isEmpty,
                "Expected \(testCase.name) to be valid; got \(result.diagnostics)"
            )
            #expect(result.manifest?.execution == testCase.expected)
        }
    }

    @Test func rejectsInvalidManifestsWithStableDiagnostics() throws {
        let cases: [(name: String, data: Data, code: ActionManifestDiagnostic.Code)] = [
            (
                "unknown schema",
                try manifestData { $0["schemaVersion"] = 2 },
                .unsupportedSchemaVersion
            ),
            (
                "invalid package version",
                try manifestData { $0["version"] = "one" },
                .invalidVersion
            ),
            (
                "incompatible runtime",
                try manifestData { $0["minRuntimeVersion"] = "2.0.0" },
                .incompatibleRuntimeVersion
            ),
            (
                "unknown strategy",
                try manifestData {
                    $0["execution"] = ["strategy": "shell", "command": "echo unsafe"]
                },
                .unknownStrategy
            ),
            (
                "unknown capability",
                try manifestData {
                    $0["execution"] = [
                        "strategy": "singleCapability",
                        "capability": "unknown.lookup"
                    ]
                    $0["permissions"] = [["kind": "localDictionary"]]
                    $0["budget"] = ["maxModelCalls": 0, "maxCapabilityCalls": 1]
                },
                .unknownCapability
            ),
            (
                "unknown permission",
                try manifestData { $0["permissions"] = [["kind": "arbitraryCommand"]] },
                .unknownPermission
            ),
            (
                "invalid budget",
                try manifestData {
                    $0["budget"] = ["maxModelCalls": -1, "maxCapabilityCalls": 0]
                },
                .invalidBudget
            ),
            (
                "missing selection requirement",
                try manifestData { $0["input"] = [:] },
                .missingSelectionRequirement
            ),
            (
                "permission and strategy mismatch",
                try manifestData { $0["permissions"] = [] },
                .permissionStrategyMismatch
            )
        ]

        for testCase in cases {
            let result = validator.validate(data: testCase.data)

            #expect(
                result.manifest == nil,
                "Expected \(testCase.name) to be rejected"
            )
            #expect(
                result.diagnostics.contains { $0.code == testCase.code },
                "Expected \(testCase.name) to report \(testCase.code.rawValue); got \(result.diagnostics)"
            )
        }
    }

    @Test func reportsMalformedJSONWithoutLeakingDecoderDetails() {
        let result = validator.validate(data: Data("not json".utf8))

        #expect(result.manifest == nil)
        #expect(
            result.diagnostics == [
                ActionManifestDiagnostic(
                    code: .invalidJSON,
                    message: "The action package manifest is not valid JSON."
                )
            ]
        )
    }

    @Test func acceptsPackageAtCurrentRuntimeVersion() throws {
        let result = validator.validate(data: try manifestData { manifest in
            manifest["minRuntimeVersion"] = "1.0.0"
        })

        #expect(result.diagnostics.isEmpty)
        #expect(result.manifest != nil)
    }

    private func manifestData(
        mutate: (inout [String: Any]) -> Void = { _ in }
    ) throws -> Data {
        var manifest: [String: Any] = [
            "schemaVersion": 1,
            "id": "community.explain",
            "version": "1.2.0",
            "minRuntimeVersion": "1.0.0",
            "display": [
                "name": "Explain clearly",
                "allowsFollowUp": true
            ],
            "input": ["selection": "required"],
            "execution": [
                "strategy": "singleCapability",
                "capability": "test.dictionary"
            ],
            "permissions": [["kind": "localDictionary"]],
            "budget": ["maxModelCalls": 0, "maxCapabilityCalls": 1],
            "output": ["kind": "text", "format": "markdown"]
        ]
        mutate(&manifest)
        return try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
    }
}
