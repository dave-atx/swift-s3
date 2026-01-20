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
