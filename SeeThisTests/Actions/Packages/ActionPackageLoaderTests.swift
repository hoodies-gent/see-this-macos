import Foundation
import Testing
@testable import SeeThis

struct ActionPackageLoaderTests {

    @Test func discoversJSONPackagesFromBundledAndUserDirectories() throws {
        let workspace = try PackageWorkspace()
        defer { workspace.remove() }
        try workspace.writeManifest(id: "bundled.explain", to: .bundled, fileName: "explain.json")
        try workspace.writeManifest(id: "community.summary", to: .user, fileName: "summary.json")
        try Data("ignored".utf8).write(to: workspace.user.appendingPathComponent("notes.txt"))

        let catalog = makeLoader().load(from: workspace.directories)

        #expect(catalog.packages.map(\.manifest.id) == ["bundled.explain", "community.summary"])
        #expect(catalog.packages.map(\.origin) == [.bundled, .user])
        #expect(catalog.packages.allSatisfy { $0.isAvailable })
        #expect(catalog.diagnostics.isEmpty)
    }

    @Test func userPackageCannotOverrideBundledPackage() throws {
        let workspace = try PackageWorkspace()
        defer { workspace.remove() }
        try workspace.writeManifest(
            id: "shared.action",
            name: "Bundled",
            to: .bundled,
            fileName: "bundled.json"
        )
        try workspace.writeManifest(
            id: "shared.action",
            name: "User override",
            to: .user,
            fileName: "override.json"
        )

        let catalog = makeLoader().load(from: workspace.directories)

        #expect(catalog.packages.count == 1)
        #expect(catalog.packages.first?.origin == .bundled)
        #expect(catalog.packages.first?.manifest.display.name == "Bundled")
        #expect(catalog.diagnostics.map(\.code) == ["package.user_conflicts_with_bundled"])
        #expect(
            catalog.diagnostics.first?.message
                == "User package 'shared.action' cannot override a bundled package."
        )
    }

    @Test func rejectsEveryPackageWithADuplicateUserID() throws {
        let workspace = try PackageWorkspace()
        defer { workspace.remove() }
        try workspace.writeManifest(id: "duplicate.action", to: .user, fileName: "first.json")
        try workspace.writeManifest(id: "duplicate.action", to: .user, fileName: "second.json")

        let catalog = makeLoader().load(from: workspace.directories)

        #expect(catalog.packages.isEmpty)
        #expect(
            catalog.diagnostics.map(\.code)
                == ["package.duplicate_id", "package.duplicate_id"]
        )
        #expect(
            catalog.diagnostics.allSatisfy {
                $0.message == "Duplicate action package id 'duplicate.action'."
            }
        )
    }

    @Test func reportsManifestValidationFailuresWithoutLoadingThem() throws {
        let workspace = try PackageWorkspace()
        defer { workspace.remove() }
        try Data("not json".utf8).write(
            to: workspace.user.appendingPathComponent("broken.json")
        )
        try workspace.writeManifest(
            id: "future.action",
            minimumRuntimeVersion: "2.0.0",
            to: .user,
            fileName: "future.json"
        )

        let catalog = makeLoader().load(from: workspace.directories)

        #expect(catalog.packages.isEmpty)
        #expect(
            Set(catalog.diagnostics.map(\.code))
                == [
                    "manifest.invalid_json",
                    "manifest.incompatible_runtime_version"
                ]
        )
    }

    @Test func keepsKnownButUnavailableCapabilityPackageVisible() throws {
        let workspace = try PackageWorkspace()
        defer { workspace.remove() }
        try workspace.writeManifest(
            id: "community.dictionary",
            to: .user,
            fileName: "dictionary.json"
        ) { manifest in
            manifest["execution"] = [
                "strategy": "singleCapability",
                "capability": "test.dictionary"
            ]
            manifest["permissions"] = [["kind": "localDictionary"]]
            manifest["budget"] = ["maxModelCalls": 0, "maxCapabilityCalls": 1]
        }
        try workspace.writeManifest(
            id: "community.unknown",
            to: .user,
            fileName: "unknown.json"
        ) { manifest in
            manifest["execution"] = [
                "strategy": "singleCapability",
                "capability": "unknown.lookup"
            ]
            manifest["permissions"] = [["kind": "localDictionary"]]
            manifest["budget"] = ["maxModelCalls": 0, "maxCapabilityCalls": 1]
        }

        let catalog = makeLoader(
            knownCapabilityIDs: ["test.dictionary"],
            availableCapabilityIDs: []
        ).load(from: workspace.directories)

        #expect(catalog.packages.map(\.manifest.id) == ["community.dictionary"])
        let package = try #require(catalog.packages.first)
        #expect(!package.isAvailable)
        #expect(
            package.availability
                == .unavailable(
                    ActionPackageDiagnostic(
                        code: "package.capability_unavailable",
                        message: "Required capability 'test.dictionary' is not available.",
                        fileName: "dictionary.json"
                    )
                )
        )
        #expect(catalog.diagnostics.map(\.code) == ["manifest.unknown_capability"])
    }

    @Test func resolvesTheProductionPackageDirectories() {
        let resourceURL = URL(fileURLWithPath: "/Applications/SeeThis.app/Contents/Resources")
        let applicationSupportURL = URL(
            fileURLWithPath: "/Users/reader/Library/Application Support"
        )

        let directories = ActionPackageDirectories(
            bundleResourceURL: resourceURL,
            applicationSupportURL: applicationSupportURL,
            bundleIdentifier: AppIdentity.bundleIdentifier
        )

        #expect(
            directories.bundled?.path
                == "/Applications/SeeThis.app/Contents/Resources/ActionPackages.bundle"
        )
        #expect(
            directories.user.path
                == "/Users/reader/Library/Application Support/io.github.hoodies-gent.seethis/ActionPackages"
        )
    }

    private func makeLoader(
        knownCapabilityIDs: Set<String> = ["test.dictionary"],
        availableCapabilityIDs: Set<String> = ["test.dictionary"]
    ) -> ActionPackageLoader {
        ActionPackageLoader(
            validator: ActionManifestValidator(
                runtimeVersion: SemanticVersion(1, 0, 0),
                knownCapabilityIDs: knownCapabilityIDs
            ),
            availableCapabilityIDs: availableCapabilityIDs
        )
    }
}

private struct PackageWorkspace {
    enum Directory: Equatable {
        case bundled
        case user
    }

    let root: URL
    let bundled: URL
    let user: URL

    var directories: ActionPackageDirectories {
        ActionPackageDirectories(bundled: bundled, user: user)
    }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActionPackageLoaderTests-\(UUID().uuidString)")
        bundled = root.appendingPathComponent("Bundled", isDirectory: true)
        user = root.appendingPathComponent("User", isDirectory: true)
        try FileManager.default.createDirectory(
            at: bundled,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: user,
            withIntermediateDirectories: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func writeManifest(
        id: String,
        name: String = "Test action",
        minimumRuntimeVersion: String = "1.0.0",
        to directory: Directory,
        fileName: String,
        mutate: (inout [String: Any]) -> Void = { _ in }
    ) throws {
        var manifest: [String: Any] = [
            "schemaVersion": 1,
            "id": id,
            "version": "1.0.0",
            "minRuntimeVersion": minimumRuntimeVersion,
            "display": [
                "name": name,
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
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        let targetDirectory = directory == .bundled ? bundled : user
        try data.write(to: targetDirectory.appendingPathComponent(fileName))
    }
}
