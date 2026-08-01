import Foundation

// Every suite must be listed here; a forgotten call silently skips it.
runPlaceholderTests()

print("\(testCount) tests, \(failureCount) failures")
exit(failureCount == 0 ? 0 : 1)
