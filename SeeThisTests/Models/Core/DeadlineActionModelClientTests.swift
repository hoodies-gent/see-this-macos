import Testing
@testable import SeeThis

struct DeadlineActionModelClientTests {

    @Test func forwardsEventsAndReturnsTheBaseResultBeforeTheDeadline() async {
        let base = ImmediateActionModelClient(
            events: [.fragment("Synthetic fragment."), .finished],
            result: .success(())
        )
        let events = DeadlineEventRecorder()
        let client = DeadlineActionModelClient(
            base: base,
            timeoutNanoseconds: 1_000_000_000
        )

        let result = await client.streamChat(
            model: "test-model",
            messages: [ChatMessage(role: .user, content: "Synthetic request.")]
        ) { event in
            await events.append(event)
        }

        guard case .success = result else {
            Issue.record("Expected the base result to succeed")
            return
        }
        #expect(await events.values() == [.fragment("Synthetic fragment."), .finished])
    }

    @Test func returnsTimeoutAndCancelsTheBaseRequestAtTheDeadline() async {
        let base = BlockingActionModelClient()
        let client = DeadlineActionModelClient(
            base: base,
            timeoutNanoseconds: 1_000_000
        )

        let result = await client.streamChat(
            model: "test-model",
            messages: []
        ) { _ in }

        #expect(failure(from: result) == .timeout)
        #expect(await base.wasCancelled())
    }

    @Test func parentCancellationCancelsTheBaseRequest() async {
        let base = BlockingActionModelClient()
        let client = DeadlineActionModelClient(
            base: base,
            timeoutNanoseconds: 10_000_000_000
        )
        let request = Task {
            await client.streamChat(
                model: "test-model",
                messages: []
            ) { _ in }
        }

        await base.waitUntilStarted()
        request.cancel()
        let result = await request.value

        #expect(failure(from: result) == .cancelled)
        #expect(await base.wasCancelled())
    }

    private func failure(from result: Result<Void, ChatFailure>) -> ChatFailure? {
        guard case let .failure(failure) = result else { return nil }
        return failure
    }
}

private struct ImmediateActionModelClient: ActionModelClient {
    let events: [ChatStreamEvent]
    let result: Result<Void, ChatFailure>

    func streamChat(
        model: String,
        messages: [ChatMessage],
        onEvent: @escaping @Sendable (ChatStreamEvent) async -> Void
    ) async -> Result<Void, ChatFailure> {
        for event in events {
            await onEvent(event)
        }
        return result
    }
}

private actor BlockingActionModelClient: ActionModelClient {
    private var started = false
    private var cancelled = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func streamChat(
        model: String,
        messages: [ChatMessage],
        onEvent: @escaping @Sendable (ChatStreamEvent) async -> Void
    ) async -> Result<Void, ChatFailure> {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }

        do {
            try await Task.sleep(nanoseconds: 10_000_000_000)
            return .success(())
        } catch {
            cancelled = true
            return .failure(.cancelled)
        }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func wasCancelled() -> Bool {
        cancelled
    }
}

private actor DeadlineEventRecorder {
    private var events: [ChatStreamEvent] = []

    func append(_ event: ChatStreamEvent) {
        events.append(event)
    }

    func values() -> [ChatStreamEvent] {
        events
    }
}
