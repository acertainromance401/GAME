import Foundation

@main
struct MotionProbe {
    @MainActor
    static func main() {
        let result = MotionRegressionChecks.run()
        for failure in result.failures { print("FAIL: \(failure)") }
        print("Motion regression checks: \(result.checks), failures: \(result.failures.count)")
        if !result.failures.isEmpty { exit(1) }
    }
}