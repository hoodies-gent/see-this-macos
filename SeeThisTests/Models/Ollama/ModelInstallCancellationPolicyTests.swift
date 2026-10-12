import Testing
@testable import SeeThis

struct ModelInstallCancellationPolicyTests {
    private let progress = OllamaPullProgress(
        status: "pulling",
        completedBytes: 1,
        totalBytes: 2
    )

    @Test func cancelledInstallKeepsAModelThatWasPresentBeforeThePull() {
        #expect(!ModelInstallCancellationPolicy.shouldDeletePartialModel(
            state: .queued,
            modelWasPresentBeforeInstall: true
        ))
        #expect(!ModelInstallCancellationPolicy.shouldDeletePartialModel(
            state: .pulling(progress),
            modelWasPresentBeforeInstall: true
        ))
        #expect(!ModelInstallCancellationPolicy.shouldDeletePartialModel(
            state: .paused(progress),
            modelWasPresentBeforeInstall: true
        ))
    }

    @Test func cancelledInstallDeletesOnlyANewPartialDownload() {
        #expect(ModelInstallCancellationPolicy.shouldDeletePartialModel(
            state: .queued,
            modelWasPresentBeforeInstall: false
        ))
        #expect(ModelInstallCancellationPolicy.shouldDeletePartialModel(
            state: .pulling(progress),
            modelWasPresentBeforeInstall: false
        ))
        #expect(ModelInstallCancellationPolicy.shouldDeletePartialModel(
            state: .paused(progress),
            modelWasPresentBeforeInstall: false
        ))
        #expect(!ModelInstallCancellationPolicy.shouldDeletePartialModel(
            state: .failed("network unavailable"),
            modelWasPresentBeforeInstall: false
        ))
        #expect(!ModelInstallCancellationPolicy.shouldDeletePartialModel(
            state: nil,
            modelWasPresentBeforeInstall: false
        ))
    }
}
