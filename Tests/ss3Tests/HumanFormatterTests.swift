import Testing
import Foundation
@testable import ss3
import SwiftS3

@Test func humanFormatterFormatsBuckets() {
    let formatter = HumanFormatter()
    let buckets = [
        Bucket(name: "bucket1", creationDate: nil, region: nil),
        Bucket(name: "bucket2", creationDate: nil, region: nil)
    ]

    let output = formatter.formatBuckets(buckets)

    #expect(output.contains("bucket1"))
    #expect(output.contains("bucket2"))
    #expect(output.contains("2 buckets"))
}

@Test func humanFormatterFormatsObjects() {
    let formatter = HumanFormatter()
    let objects = [
        S3Object(
            key: "file.txt",
            lastModified: Date(timeIntervalSince1970: 1705312200),
            etag: nil,
            size: 1234,
            storageClass: nil,
            owner: nil
        )
    ]

    let output = formatter.formatObjects(objects, prefixes: [])

    #expect(output.contains("file.txt"))
    #expect(output.contains("1.2 KB"))
    #expect(output.contains("1 item"))
}

@Test func humanFormatterFormatsPrefixes() {
    let formatter = HumanFormatter()
    let output = formatter.formatObjects([], prefixes: ["logs/", "data/"])

    #expect(output.contains("logs/"))
    #expect(output.contains("data/"))
}

@Test func humanFormatterFormatsSize() {
    let formatter = HumanFormatter()

    #expect(formatter.formatSize(0) == "0 B")
    #expect(formatter.formatSize(512) == "512 B")
    #expect(formatter.formatSize(1024) == "1.0 KB")
    #expect(formatter.formatSize(1536) == "1.5 KB")
    #expect(formatter.formatSize(1048576) == "1.0 MB")
    #expect(formatter.formatSize(1073741824) == "1.0 GB")
}

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
