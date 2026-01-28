import Testing
import Foundation
@testable import ss3
import SwiftS3

@Test func compactSizeFormatsBytes() {
    let formatter = HumanFormatter()

    #expect(formatter.formatCompactSize(0) == "   0B")
    #expect(formatter.formatCompactSize(1) == "   1B")
    #expect(formatter.formatCompactSize(999) == " 999B")
}

@Test func compactSizeFormatsKilobytes() {
    let formatter = HumanFormatter()

    #expect(formatter.formatCompactSize(1024) == " 1.0K")
    #expect(formatter.formatCompactSize(1536) == " 1.5K")
    #expect(formatter.formatCompactSize(10240) == "10.0K")
    #expect(formatter.formatCompactSize(102400) == " 100K")
}

@Test func compactSizeFormatsMegabytes() {
    let formatter = HumanFormatter()

    #expect(formatter.formatCompactSize(1048576) == " 1.0M")
    #expect(formatter.formatCompactSize(104857600) == " 100M")
}

@Test func compactSizeFormatsLargeValues() {
    let formatter = HumanFormatter()

    #expect(formatter.formatCompactSize(1073741824) == " 1.0G")
    #expect(formatter.formatCompactSize(1099511627776) == " 1.0T")
}

@Test func lsDateFormatsRecentDates() {
    let formatter = HumanFormatter()
    let calendar = Calendar.current
    let now = Date()
    let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now)!

    let formatted = formatter.formatLsDate(oneMonthAgo)

    #expect(formatted.count == 12)
    #expect(formatted.contains(":"))
}

@Test func lsDateFormatsOldDates() {
    let formatter = HumanFormatter()
    let calendar = Calendar.current
    let now = Date()
    let eightMonthsAgo = calendar.date(byAdding: .month, value: -8, to: now)!

    let formatted = formatter.formatLsDate(eightMonthsAgo)

    #expect(formatted.count == 12)
    #expect(!formatted.contains(":"))
    #expect(formatted.contains("202"))  // Has year
}

@Test func lsDateEdgeCaseExactlySixMonths() {
    let formatter = HumanFormatter()
    let now = Date()
    let sixMonthsAgo = now.addingTimeInterval(-182 * 24 * 60 * 60)

    let formatted = formatter.formatLsDate(sixMonthsAgo)

    #expect(formatted.count == 12)
    #expect(!formatted.contains(":"))
    #expect(formatted.contains("202"))  // Has year
}

@Test func formatErrorShowsMessage() {
    let formatter = HumanFormatter()
    let error = S3APIError(
        code: .accessDenied,
        message: "Access denied",
        resource: nil,
        requestId: nil
    )

    let result = formatter.formatError(error, verbose: false)

    #expect(result.contains("Access denied"))
    #expect(result.contains("Hint:"))
}
