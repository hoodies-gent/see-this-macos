import Foundation

nonisolated struct DeadlineActionModelClient: ActionModelClient {
    private let base: any ActionModelClient
    private let timeoutNanoseconds: UInt64

    init(base: any ActionModelClient, timeoutNanoseconds: UInt64) {
        self.base = base
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    func streamChat(
        model: String,
        messages: [ChatMessage],
        onEvent: @escaping @Sendable (ChatStreamEvent) async -> Void
    ) async -> Result<Void, ChatFailure> {
        await withTaskGroup(of: Result<Void, ChatFailure>.self) { group in
            group.addTask {
                await base.streamChat(
                    model: model,
                    messages: messages,
                    onEvent: onEvent
                )
            }
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    return .failure(.timeout)
                } catch {
                    return .failure(.cancelled)
                }
            }

            let result = await group.next() ?? .failure(.cancelled)
            group.cancelAll()
            return result
        }
    }
}
