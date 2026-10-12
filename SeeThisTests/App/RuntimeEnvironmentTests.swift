import Testing
@testable import SeeThis

struct RuntimeEnvironmentTests {
    @Test func unitTestsAreDetectedInsideTheHostApp() {
        #expect(RuntimeEnvironment.isRunningUnitTests)
    }
}
