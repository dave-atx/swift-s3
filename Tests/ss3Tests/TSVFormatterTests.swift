import Testing
import Foundation
@testable import ss3
import SwiftS3

@Test func tsvFormatterFormatsBuckets() {
    let formatter = TSVFormatter()
    let buckets = [
        Bucket(name: "bucket1", creationDate: nil, region: nil),
        Bucket(name: "bucket2", creationDate: nil, region: nil)
    ]

    let output = formatter.formatBuckets(buckets)
    let lines = output.split(separator: "\n")

    #expect(lines.count == 2)
    #expect(lines[0].contains("bucket1"))
    #expect(lines[1].contains("bucket2"))
}

@Test func tsvFormatterFormatsObjects() {
    let formatter = TSVFormatter()
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

    #expect(output.contains("file.txt\t1234\t"))
}
