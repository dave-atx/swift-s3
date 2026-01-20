import Testing
import Foundation
@testable import SwiftS3

@Test func ownerEquality() async throws {
    let owner1 = Owner(id: "123", displayName: "Alice")
    let owner2 = Owner(id: "123", displayName: "Alice")
    let owner3 = Owner(id: "456", displayName: "Bob")

    #expect(owner1 == owner2)
    #expect(owner1 != owner3)
}

@Test func bucketProperties() async throws {
    let date = Date()
    let bucket = Bucket(name: "my-bucket", creationDate: date, region: "us-east-1")

    #expect(bucket.name == "my-bucket")
    #expect(bucket.creationDate == date)
    #expect(bucket.region == "us-east-1")
}

@Test func s3ObjectProperties() async throws {
    let obj = S3Object(
        key: "folder/file.txt",
        lastModified: nil,
        etag: "\"abc123\"",
        size: 1024,
        storageClass: "STANDARD",
        owner: nil
    )

    #expect(obj.key == "folder/file.txt")
    #expect(obj.size == 1024)
    #expect(obj.storageClass == "STANDARD")
}

@Test func objectMetadataProperties() async throws {
    let metadata = ObjectMetadata(
        contentLength: 2048,
        contentType: "application/json",
        etag: "\"def456\"",
        lastModified: nil,
        versionId: "v1",
        metadata: ["author": "test"]
    )

    #expect(metadata.contentLength == 2048)
    #expect(metadata.contentType == "application/json")
    #expect(metadata.metadata["author"] == "test")
}
