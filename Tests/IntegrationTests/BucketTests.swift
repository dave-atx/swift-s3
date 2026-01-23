import Testing
import Foundation
@testable import SwiftS3

@Suite("Bucket Operations", .serialized)
struct BucketTests {
    init() async throws {
        try await MinioTestServer.shared.ensureRunning()
    }

    @Test
    func createAndDeleteBucket() async throws {
        let client = TestConfig.createClient()
        let bucketName = TestConfig.uniqueBucketName(prefix: "create")

        // Create bucket
        try await client.createBucket(bucketName)

        // Verify it exists by listing
        let result = try await client.listBuckets()
        #expect(result.buckets.contains { $0.name == bucketName })

        // Cleanup
        try await client.deleteBucket(bucketName)

        // Verify it's gone
        let afterDelete = try await client.listBuckets()
        #expect(!afterDelete.buckets.contains { $0.name == bucketName })
    }

    @Test
    func listBuckets() async throws {
        let client = TestConfig.createClient()
        let bucket1 = TestConfig.uniqueBucketName(prefix: "list1")
        let bucket2 = TestConfig.uniqueBucketName(prefix: "list2")

        // Create two buckets
        try await client.createBucket(bucket1)
        defer { Task { await cleanupBucket(client, bucket1) } }

        try await client.createBucket(bucket2)
        defer { Task { await cleanupBucket(client, bucket2) } }

        // List and verify both exist
        let result = try await client.listBuckets()
        #expect(result.buckets.contains { $0.name == bucket1 })
        #expect(result.buckets.contains { $0.name == bucket2 })
    }

    @Test
    func deleteBucketThatDoesNotExist() async throws {
        let client = TestConfig.createClient()
        let bucketName = "nonexistent-bucket-\(UUID().uuidString.prefix(8).lowercased())"

        // Attempting to delete non-existent bucket should throw
        await #expect(throws: (any Error).self) {
            try await client.deleteBucket(bucketName)
        }
    }

    @Test
    func createDuplicateBucket() async throws {
        let client = TestConfig.createClient()
        let bucketName = TestConfig.uniqueBucketName(prefix: "dup")

        try await client.createBucket(bucketName)
        defer { Task { await cleanupBucket(client, bucketName) } }

        // Creating same bucket again should throw
        await #expect(throws: (any Error).self) {
            try await client.createBucket(bucketName)
        }
    }
}
