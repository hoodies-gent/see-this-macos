import AppKit
import Foundation

// Local-Ollama implementation of ModelProvider. All chat + model-management
// traffic flows through here; UI callers hold the ModelProvider surface.
struct OllamaProvider: ModelProvider {
    static let defaultModelName = "gemma3:4b"
    static let serviceEndpoint = URL(string: "http://127.0.0.1:11434")!
    nonisolated static let chatEndpoint = URL(string: "http://127.0.0.1:11434/api/chat")!
    static let tagsEndpoint = URL(string: "http://127.0.0.1:11434/api/tags")!
    static let pullEndpoint = URL(string: "http://127.0.0.1:11434/api/pull")!
    static let deleteEndpoint = URL(string: "http://127.0.0.1:11434/api/delete")!
    static let showEndpoint = URL(string: "http://127.0.0.1:11434/api/show")!

    func streamChat(
        model: String,
        messages: [ChatMessage],
        onEvent: @escaping @Sendable (ChatStreamEvent) async -> Void
    ) async -> Result<Void, ChatFailure> {
        let body = OllamaChatBody(
            model: model,
            messages: messages.map { OllamaChatBody.Message(role: $0.role.rawValue, content: $0.content) },
            stream: true,
            think: false,
            options: OllamaChatBody.Options(numPredict: 512)
        )
        guard let requestData = try? JSONEncoder().encode(body) else {
            return .failure(.invalidResponse)
        }

        var request = URLRequest(url: Self.chatEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestData

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.invalidResponse)
            }
            guard httpResponse.statusCode != 404 else { return .failure(.modelUnavailable(model: model)) }
            guard (200...299).contains(httpResponse.statusCode) else { return .failure(.invalidResponse) }
            var receivedFragment = false
            for try await line in bytes.lines {
                if Task.isCancelled { return .failure(.cancelled) }
                guard !line.isEmpty else { continue }
                guard let event = OllamaStreamDecoder.decode(line: line) else {
                    return .failure(.invalidResponse)
                }
                if case .fragment = event { receivedFragment = true }
                await onEvent(event)
                if case .finished = event {
                    return receivedFragment ? .success(()) : .failure(.invalidResponse)
                }
            }
            return .failure(.invalidResponse)
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            if Task.isCancelled { return .failure(.cancelled) }
            return .failure(.unavailable)
        }
    }

    func listModels() async -> Result<[ModelDescriptor], ChatFailure> {
        do {
            let (data, response) = try await URLSession.shared.data(from: Self.tagsEndpoint)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let tagsResponse = try? JSONDecoder().decode(OllamaTagsResponse.self, from: data) else {
                return .failure(.unavailable)
            }
            return .success(tagsResponse.installedModels)
        } catch {
            return .failure(.unavailable)
        }
    }

    func showModel(name: String) async -> ModelDescriptor? {
        struct ShowBody: Encodable { let name: String }
        guard let requestData = try? JSONEncoder().encode(ShowBody(name: name)) else {
            return nil
        }
        var request = URLRequest(url: Self.showEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            let contextLength: Int? = {
                guard let info = object["model_info"] as? [String: Any] else { return nil }
                // Key is prefixed by architecture (gemma3.context_length, etc.);
                // match on suffix so we don't hard-code the arch.
                for (key, value) in info where key.hasSuffix(".context_length") {
                    if let intValue = value as? Int { return intValue }
                    if let numberValue = value as? NSNumber { return numberValue.intValue }
                }
                return nil
            }()
            let capabilities = (object["capabilities"] as? [String]) ?? []
            return ModelDescriptor(
                id: name,
                contextLength: contextLength,
                capabilities: capabilities
            )
        } catch {
            return nil
        }
    }

    func pullModel(
        name: String,
        onProgress: @escaping @Sendable (ModelPullProgress) async -> Void
    ) async -> Result<Void, ChatFailure> {
        struct PullBody: Encodable {
            let name: String
            let stream: Bool
        }
        struct PullChunk: Decodable {
            let status: String?
            let completed: Int64?
            let total: Int64?
            let error: String?
        }
        guard let requestData = try? JSONEncoder().encode(PullBody(name: name, stream: true)) else {
            return .failure(.invalidResponse)
        }
        var request = URLRequest(url: Self.pullEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestData
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.invalidResponse)
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                var body = Data()
                let deadline = Date().addingTimeInterval(3)
                do {
                    for try await byte in bytes.prefix(8_192) {
                        if Task.isCancelled { return .failure(.cancelled) }
                        if Date() > deadline { break }
                        body.append(byte)
                    }
                } catch {}
                if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                   let error = json["error"] as? String {
                    return .failure(.pullFailed(reason: error))
                }
                return .failure(.unavailable)
            }
            for try await line in bytes.lines {
                if Task.isCancelled { return .failure(.cancelled) }
                guard !line.isEmpty,
                      let data = line.data(using: .utf8),
                      let chunk = try? JSONDecoder().decode(PullChunk.self, from: data) else {
                    continue
                }
                if let error = chunk.error {
                    return .failure(.pullFailed(reason: error))
                }
                await onProgress(ModelPullProgress(
                    status: chunk.status ?? "",
                    completedBytes: chunk.completed,
                    totalBytes: chunk.total
                ))
                if chunk.status == "success" {
                    return .success(())
                }
            }
            return .failure(.pullFailed(reason: "The download ended without a success confirmation."))
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            if Task.isCancelled { return .failure(.cancelled) }
            return .failure(.unavailable)
        }
    }

    static func isInstalled(_ name: String, among installedIDs: [String]) -> Bool {
        let requested = normalizedModelName(name)
        return installedIDs.contains { normalizedModelName($0) == requested }
    }

    private static func normalizedModelName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.contains(":") ? trimmed : trimmed + ":latest"
    }

    func deleteModel(name: String) async -> Result<Void, ChatFailure> {
        struct DeleteBody: Encodable { let name: String }
        guard let requestData = try? JSONEncoder().encode(DeleteBody(name: name)) else {
            return .failure(.invalidResponse)
        }
        var request = URLRequest(url: Self.deleteEndpoint)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestData
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.invalidResponse)
            }
            if httpResponse.statusCode == 404 { return .success(()) }
            guard (200...299).contains(httpResponse.statusCode) else {
                return .failure(.invalidResponse)
            }
            return .success(())
        } catch {
            return .failure(.unavailable)
        }
    }

    func waitForServiceReady(
        timeoutSeconds: Double,
        pollIntervalSeconds: Double
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        let pollNanoseconds = UInt64(pollIntervalSeconds * 1_000_000_000)
        while Date() < deadline {
            if Task.isCancelled { return false }
            if case .success = await listModels() {
                return true
            }
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
        return false
    }

    @MainActor
    func startService() async -> Bool {
        switch OllamaInstallation.detected {
        case .app(let url):
            return await launchApp(at: url)
        case .cli(let url):
            return launchCLIServe(binary: url)
        case .none:
            return false
        }
    }

    @MainActor
    func stopService() async -> Bool {
        var terminated = false
        for app in NSWorkspace.shared.runningApplications {
            guard let path = app.bundleURL?.path,
                  OllamaInstallation.appPaths.contains(path) else { continue }
            _ = app.terminate()
            terminated = true
        }
        let killed = await killOllamaServe()
        return terminated || killed
    }

    @MainActor
    private func launchApp(at url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    private func launchCLIServe(binary: URL) -> Bool {
        let process = Process()
        process.executableURL = binary
        process.arguments = ["serve"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    private func killOllamaServe() async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-f", "ollama serve"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { p in
                continuation.resume(returning: p.terminationStatus == 0)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
}

// Wire-format for /api/chat. Kept separate from ChatMessage so the protocol
// stays provider-agnostic (roles as an enum) while transport serializes
// exactly the string Ollama expects.
private nonisolated struct OllamaChatBody: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct Options: Encodable {
        let numPredict: Int
        enum CodingKeys: String, CodingKey {
            case numPredict = "num_predict"
        }
    }

    let model: String
    let messages: [Message]
    let stream: Bool
    let think: Bool
    let options: Options
}

// Line-by-line decoder for /api/chat streaming responses.
private nonisolated enum OllamaStreamDecoder {
    private struct StreamResponse: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
        let done: Bool
    }

    static func decode(line: String) -> ChatStreamEvent? {
        guard
            let data = line.data(using: .utf8),
            let response = try? JSONDecoder().decode(StreamResponse.self, from: data)
        else {
            return nil
        }
        if response.done {
            return .finished
        }
        guard !response.message.content.isEmpty else { return nil }
        return .fragment(response.message.content)
    }
}
