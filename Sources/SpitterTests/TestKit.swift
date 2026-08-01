import Foundation

// Minimal assertion harness. Neither XCTest nor Swift Testing is importable when only the
// Command Line Tools are installed, so the test suite ships as a plain executable target
// that runs identically on a dev machine and on CI.
// Single-threaded runner; `nonisolated(unsafe)` keeps Swift 6 strict concurrency happy
// without dragging the whole harness onto an actor.
nonisolated(unsafe) var testCount = 0
nonisolated(unsafe) var failureCount = 0

func expect(_ condition: Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
    if !condition {
        failureCount += 1
        print("  FAIL [\(file):\(line)] \(message)")
    }
}

func expectEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if actual != expected {
        failureCount += 1
        print("  FAIL [\(file):\(line)] \(message): \(actual) != \(expected)")
    }
}

func expectNil<T>(_ value: T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    if value != nil {
        failureCount += 1
        print("  FAIL [\(file):\(line)] \(message): expected nil, got \(value!)")
    }
}

func test(_ name: String, _ body: () throws -> Void) {
    testCount += 1
    print("- \(name)")
    do {
        try body()
    } catch {
        failureCount += 1
        print("  FAIL threw \(error)")
    }
}
