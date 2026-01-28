import Testing
import Foundation
@testable import ss3
import SwiftS3

@Test func shortFormatObjectsShowsNamesOnly() {
    let formatter = ListFormatter(longFormat: false, sortByTime: false)
    let objects = [
        S3Object(key: "file1.txt", lastModified: nil, etag: nil, size: 1024, storageClass: nil, owner: nil),
        S3Object(key: "file2.txt", lastModified: nil, etag: nil, size: 2048, storageClass: nil, owner: nil)
    ]

    let result = formatter.formatObjects(objects, prefixes: ["folder/"])
    let lines = result.split(separator: "\n").map(String.init)

    #expect(lines.count == 3)
    #expect(lines[0] == "file1.txt")
    #expect(lines[1] == "file2.txt")
    #expect(lines[2] == "folder/")
}

@Test func longFormatObjectsShowsSizeDateName() {
    let formatter = ListFormatter(longFormat: true, sortByTime: false)
    let date = Date(timeIntervalSince1970: 1705312200)
    let objects = [
        S3Object(key: "file.txt", lastModified: date, etag: nil, size: 2048, storageClass: nil, owner: nil)
    ]

    let result = formatter.formatObjects(objects, prefixes: [])
    let lines = result.split(separator: "\n").map(String.init)

    #expect(lines.count == 1)
    // Should contain size, date, and filename
    #expect(lines[0].contains("file.txt"))
    // Check for compact size format (should be something like " 2.0K")
    #expect(lines[0].contains("K"))
    // Check for date format
    #expect(lines[0].count > 20)  // Should be longer due to date
}

@Test func longFormatDirectoriesShowNamesOnly() {
    let formatter = ListFormatter(longFormat: true, sortByTime: false)
    let result = formatter.formatObjects([], prefixes: ["logs/", "data/"])
    let lines = result.split(separator: "\n").map(String.init)

    #expect(lines.count == 2)
    #expect(lines[0] == "data/")
    #expect(lines[1] == "logs/")
}

@Test func sortByTimeOrdersFilesFirst() {
    let formatter = ListFormatter(longFormat: false, sortByTime: true)
    let now = Date()
    let oneHourAgo = now.addingTimeInterval(-3600)
    let objects = [
        S3Object(key: "older.txt", lastModified: oneHourAgo, etag: nil, size: 1024, storageClass: nil, owner: nil),
        S3Object(key: "newer.txt", lastModified: now, etag: nil, size: 1024, storageClass: nil, owner: nil)
    ]

    let result = formatter.formatObjects(objects, prefixes: ["folder/"])
    let lines = result.split(separator: "\n").map(String.init)

    #expect(lines.count == 3)
    // Newer should come first when sorting by time
    #expect(lines[0] == "newer.txt")
    #expect(lines[1] == "older.txt")
    // Directories come after files
    #expect(lines[2] == "folder/")
}

@Test func shortFormatBucketsShowsNamesOnly() {
    let formatter = ListFormatter(longFormat: false, sortByTime: false)
    let buckets = [
        Bucket(name: "bucket1", creationDate: nil, region: nil),
        Bucket(name: "bucket2", creationDate: nil, region: nil)
    ]

    let result = formatter.formatBuckets(buckets)
    let lines = result.split(separator: "\n").map(String.init)

    #expect(lines.count == 2)
    #expect(lines[0] == "bucket1")
    #expect(lines[1] == "bucket2")
}

@Test func longFormatBucketsShowsDateName() {
    let formatter = ListFormatter(longFormat: true, sortByTime: false)
    let date = Date(timeIntervalSince1970: 1705312200)
    let buckets = [
        Bucket(name: "mybucket", creationDate: date, region: nil)
    ]

    let result = formatter.formatBuckets(buckets)
    let lines = result.split(separator: "\n").map(String.init)

    #expect(lines.count == 1)
    // Should contain date and bucket name
    #expect(lines[0].contains("mybucket"))
    // Check for date format
    #expect(lines[0].count > 10)  // Should be longer due to date
}

@Test func sortByTimeSortsBucketsByCreation() {
    let formatter = ListFormatter(longFormat: false, sortByTime: true)
    let now = Date()
    let oneHourAgo = now.addingTimeInterval(-3600)
    let buckets = [
        Bucket(name: "older-bucket", creationDate: oneHourAgo, region: nil),
        Bucket(name: "newer-bucket", creationDate: now, region: nil)
    ]

    let result = formatter.formatBuckets(buckets)
    let lines = result.split(separator: "\n").map(String.init)

    #expect(lines.count == 2)
    // Newer should come first when sorting by time
    #expect(lines[0] == "newer-bucket")
    #expect(lines[1] == "older-bucket")
}
