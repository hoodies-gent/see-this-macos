import Foundation

nonisolated struct ActionPackageDirectories: Equatable, Sendable {
    let bundled: URL?
    let user: URL

    init(bundled: URL?, user: URL) {
        self.bundled = bundled
        self.user = user
    }

    init(
        bundleResourceURL: URL?,
        applicationSupportURL: URL,
        bundleIdentifier: String
    ) {
        bundled = bundleResourceURL?.appendingPathComponent(
            "ActionPackages.bundle",
            isDirectory: true
        )
        user = applicationSupportURL
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("ActionPackages", isDirectory: true)
    }

    static func production(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> ActionPackageDirectories {
        let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return ActionPackageDirectories(
            bundleResourceURL: bundle.resourceURL,
            applicationSupportURL: applicationSupportURL,
            bundleIdentifier: bundle.bundleIdentifier ?? AppIdentity.bundleIdentifier
        )
    }
}

nonisolated enum ActionPackageOrigin: Equatable, Sendable {
    case bundled
    case user
}

nonisolated struct ActionPackageDiagnostic: Equatable, Sendable, CustomStringConvertible {
    let code: String
    let message: String
    let fileName: String

    var description: String {
        "\(code): \(message) [\(fileName)]"
    }
}

nonisolated enum ActionPackageAvailability: Equatable, Sendable {
    case available
    case unavailable(ActionPackageDiagnostic)
}

nonisolated struct LoadedActionPackage: Equatable, Sendable {
    let manifest: ActionManifestV1
    let origin: ActionPackageOrigin
    let fileURL: URL?
    let availability: ActionPackageAvailability

    var isAvailable: Bool {
        availability == .available
    }
}

nonisolated struct ActionPackageCatalog: Equatable, Sendable {
    let packages: [LoadedActionPackage]
    let diagnostics: [ActionPackageDiagnostic]
}

nonisolated struct ActionPackageLoader {
    private let validator: ActionManifestValidator
    private let availableCapabilityIDs: Set<String>
    private let fileManager: FileManager

    init(
        validator: ActionManifestValidator,
        availableCapabilityIDs: Set<String>,
        fileManager: FileManager = .default
    ) {
        self.validator = validator
        self.availableCapabilityIDs = availableCapabilityIDs
        self.fileManager = fileManager
    }

    func load(from directories: ActionPackageDirectories) -> ActionPackageCatalog {
        var diagnostics: [ActionPackageDiagnostic] = []
        let bundledCandidates = candidates(
            at: directories.bundled,
            origin: .bundled,
            diagnostics: &diagnostics
        )
        let userCandidates = candidates(
            at: directories.user,
            origin: .user,
            diagnostics: &diagnostics
        )

        let bundledIDs = Set(bundledCandidates.compactMap(\.declaredID))
        let bundledDuplicateIDs = duplicateIDs(in: bundledCandidates)
        let userDuplicateIDs = duplicateIDs(in: userCandidates)
        var packages: [LoadedActionPackage] = []

        for candidate in bundledCandidates {
            if let id = candidate.declaredID, bundledDuplicateIDs.contains(id) {
                diagnostics.append(duplicateDiagnostic(id: id, candidate: candidate))
                continue
            }
            validate(candidate, packages: &packages, diagnostics: &diagnostics)
        }

        for candidate in userCandidates {
            if let id = candidate.declaredID, bundledIDs.contains(id) {
                diagnostics.append(
                    ActionPackageDiagnostic(
                        code: "package.user_conflicts_with_bundled",
                        message: "User package '\(id)' cannot override a bundled package.",
                        fileName: candidate.fileURL.lastPathComponent
                    )
                )
                continue
            }
            if let id = candidate.declaredID, userDuplicateIDs.contains(id) {
                diagnostics.append(duplicateDiagnostic(id: id, candidate: candidate))
                continue
            }
            validate(candidate, packages: &packages, diagnostics: &diagnostics)
        }

        return ActionPackageCatalog(packages: packages, diagnostics: diagnostics)
    }

    private func candidates(
        at directory: URL?,
        origin: ActionPackageOrigin,
        diagnostics: inout [ActionPackageDiagnostic]
    ) -> [Candidate] {
        guard let directory,
              fileManager.fileExists(atPath: directory.path) else {
            return []
        }

        let fileURLs: [URL]
        do {
            fileURLs = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            diagnostics.append(
                ActionPackageDiagnostic(
                    code: "package.directory_unreadable",
                    message: "The action package directory could not be read.",
                    fileName: directory.lastPathComponent
                )
            )
            return []
        }

        return fileURLs.compactMap { fileURL in
            do {
                let data = try Data(contentsOf: fileURL)
                return Candidate(
                    data: data,
                    declaredID: declaredID(in: data),
                    origin: origin,
                    fileURL: fileURL
                )
            } catch {
                diagnostics.append(
                    ActionPackageDiagnostic(
                        code: "package.manifest_unreadable",
                        message: "The action package manifest could not be read.",
                        fileName: fileURL.lastPathComponent
                    )
                )
                return nil
            }
        }
    }

    private func validate(
        _ candidate: Candidate,
        packages: inout [LoadedActionPackage],
        diagnostics: inout [ActionPackageDiagnostic]
    ) {
        let result = validator.validate(data: candidate.data)
        guard let manifest = result.manifest else {
            diagnostics.append(
                contentsOf: result.diagnostics.map {
                    ActionPackageDiagnostic(
                        code: $0.code.rawValue,
                        message: $0.message,
                        fileName: candidate.fileURL.lastPathComponent
                    )
                }
            )
            return
        }

        packages.append(
            LoadedActionPackage(
                manifest: manifest,
                origin: candidate.origin,
                fileURL: candidate.fileURL,
                availability: availability(
                    for: manifest,
                    fileName: candidate.fileURL.lastPathComponent
                )
            )
        )
    }

    private func availability(
        for manifest: ActionManifestV1,
        fileName: String
    ) -> ActionPackageAvailability {
        let missingCapabilityIDs = Set(manifest.execution.capabilityIDs)
            .subtracting(availableCapabilityIDs)
            .sorted()
        guard !missingCapabilityIDs.isEmpty else {
            return .available
        }

        let message: String
        if missingCapabilityIDs.count == 1 {
            message = "Required capability '\(missingCapabilityIDs[0])' is not available."
        } else {
            let ids = missingCapabilityIDs.map { "'\($0)'" }.joined(separator: ", ")
            message = "Required capabilities \(ids) are not available."
        }
        return .unavailable(
            ActionPackageDiagnostic(
                code: "package.capability_unavailable",
                message: message,
                fileName: fileName
            )
        )
    }

    private func duplicateIDs(in candidates: [Candidate]) -> Set<String> {
        let counts = candidates.reduce(into: [String: Int]()) { counts, candidate in
            guard let id = candidate.declaredID else { return }
            counts[id, default: 0] += 1
        }
        return Set(counts.compactMap { id, count in count > 1 ? id : nil })
    }

    private func duplicateDiagnostic(
        id: String,
        candidate: Candidate
    ) -> ActionPackageDiagnostic {
        ActionPackageDiagnostic(
            code: "package.duplicate_id",
            message: "Duplicate action package id '\(id)'.",
            fileName: candidate.fileURL.lastPathComponent
        )
    }

    private func declaredID(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary["id"] as? String
    }
}

private nonisolated struct Candidate {
    let data: Data
    let declaredID: String?
    let origin: ActionPackageOrigin
    let fileURL: URL
}

private extension ActionPackageExecutionStrategy {
    var capabilityIDs: [String] {
        switch self {
        case let .singleCapability(capabilityID):
            [capabilityID]
        case let .boundedAgent(_, capabilityIDs):
            capabilityIDs
        }
    }
}
