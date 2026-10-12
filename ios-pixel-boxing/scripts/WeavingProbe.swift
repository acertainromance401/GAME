import Foundation
import XCTest

@main
struct WeavingProbe {
    @MainActor
    static func main() {
        let suite = WeavingTests.defaultTestSuite
        suite.run()
        guard let result = suite.testRun else {
            print("FAIL: XCTest produced no run")
            exit(1)
        }
        print("Weaving XCTest: \(result.executionCount) executed, \(result.totalFailureCount) failures")
        if result.executionCount == 0 || !result.hasSucceeded { exit(1) }
    }
}