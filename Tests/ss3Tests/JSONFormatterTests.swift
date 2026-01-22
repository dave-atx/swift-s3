import Testing
import Foundation
@testable import ss3
import SwiftS3

@Test func jsonFormatterFormatsBuckets() throws {
    let formatter = JSONFormatter()
    let buckets = [
        Bucket(name: "bucket1", creationDate: nil, region: nil)
    ]

    let output = formatter.formatBuckets(buckets)

    #expect(output.contains("\"name\":\"bucket1\""))
}

@Test func jsonFormatterFormatsObjects() throws {
    let formatter = JSONFormatter()
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

    #expect(output.contains("\"key\":\"file.txt\""))
    #expect(output.contains("\"size\":1234"))
}
