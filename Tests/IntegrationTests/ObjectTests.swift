import Testing
import Foundation
@testable import SwiftS3

@Suite("Object Operations", .serialized)
struct ObjectTests {
    init() async throws {
        try await MinioTestServer.shared.ensureRunning()
    }

    @Test
    func putAndGetObject() async throws {
        let client = TestConfig.createClient()
        let bucket = TestConfig.uniqueBucketName(prefix: "putget")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucket(client, bucket) } }

        let key = "test-object.txt"
        let content = "Hello, World!"
        let data = Data(content.utf8)

        // Put object
        let etag = try await client.putObject(bucket: bucket, key: key, data: data, contentType: "text/plain")
        #expect(!etag.isEmpty)

        // Get object
        let (retrievedData, metadata) = try await client.getObject(bucket: bucket, key: key)
        #expect(String(data: retrievedData, encoding: .utf8) == content)
        #expect(metadata.contentType == "text/plain")
        #expect(metadata.contentLength == Int64(data.count))
    }

    @Test
    func putObjectWithMetadata() async throws {
        let client = TestConfig.createClient()
        let bucket = TestConfig.uniqueBucketName(prefix: "meta")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucket(client, bucket) } }

        let key = "metadata-test.txt"
        let data = Data("test".utf8)
        let customMetadata = ["author": "test-suite", "version": "1.0"]

        _ = try await client.putObject(
            bucket: bucket,
            key: key,
            data: data,
            metadata: customMetadata
        )

        let metadata = try await client.headObject(bucket: bucket, key: key)
        #expect(metadata.metadata["author"] == "test-suite")
        #expect(metadata.metadata["version"] == "1.0")
    }

    @Test
    func listObjects() async throws {
        let client = TestConfig.createClient()
        let bucket = TestConfig.uniqueBucketName(prefix: "listobj")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucket(client, bucket) } }

        // Upload multiple objects
        for idx in 1...3 {
            let data = Data("content \(idx)".utf8)
            _ = try await client.putObject(bucket: bucket, key: "file\(idx).txt", data: data)
        }

        // List objects
        let result = try await client.listObjects(bucket: bucket)
        #expect(result.objects.count == 3)
        #expect(result.objects.contains { $0.key == "file1.txt" })
        #expect(result.objects.contains { $0.key == "file2.txt" })
        #expect(result.objects.contains { $0.key == "file3.txt" })
    }

    @Test
    func listObjectsWithPrefix() async throws {
        let client = TestConfig.createClient()
        let bucket = TestConfig.uniqueBucketName(prefix: "prefix")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucket(client, bucket) } }

        // Upload objects with different prefixes
        _ = try await client.putObject(bucket: bucket, key: "docs/readme.txt", data: Data("readme".utf8))
        _ = try await client.putObject(bucket: bucket, key: "docs/guide.txt", data: Data("guide".utf8))
        _ = try await client.putObject(bucket: bucket, key: "images/logo.png", data: Data("logo".utf8))

        // List with prefix
        let docsResult = try await client.listObjects(bucket: bucket, prefix: "docs/")
        #expect(docsResult.objects.count == 2)
        #expect(docsResult.objects.allSatisfy { $0.key.hasPrefix("docs/") })

        let imagesResult = try await client.listObjects(bucket: bucket, prefix: "images/")
        #expect(imagesResult.objects.count == 1)
    }

    @Test
    func listObjectsWithDelimiter() async throws {
        let client = TestConfig.createClient()
        let bucket = TestConfig.uniqueBucketName(prefix: "delim")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucket(client, bucket) } }

        // Upload objects in folder structure
        _ = try await client.putObject(bucket: bucket, key: "folder1/file1.txt", data: Data("f1".utf8))
        _ = try await client.putObject(bucket: bucket, key: "folder1/file2.txt", data: Data("f2".utf8))
        _ = try await client.putObject(bucket: bucket, key: "folder2/file3.txt", data: Data("f3".utf8))
        _ = try await client.putObject(bucket: bucket, key: "root.txt", data: Data("root".utf8))

        // List with delimiter to get "folders"
        let result = try await client.listObjects(bucket: bucket, delimiter: "/")
        #expect(result.objects.count == 1) // Just root.txt
        #expect(result.objects.first?.key == "root.txt")
        #expect(result.commonPrefixes.count == 2) // folder1/ and folder2/
        #expect(result.commonPrefixes.contains("folder1/"))
        #expect(result.commonPrefixes.contains("folder2/"))
    }

    @Test
    func headObject() async throws {
        let client = TestConfig.createClient()
        let bucket = TestConfig.uniqueBucketName(prefix: "head")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucket(client, bucket) } }

        let data = Data("test content for head".utf8)
        _ = try await client.putObject(bucket: bucket, key: "head-test.txt", data: data, contentType: "text/plain")

        let metadata = try await client.headObject(bucket: bucket, key: "head-test.txt")
        #expect(metadata.contentLength == Int64(data.count))
        #expect(metadata.contentType == "text/plain")
        #expect(metadata.etag != nil)
    }

    @Test
    func deleteObject() async throws {
        let client = TestConfig.createClient()
        let bucket = TestConfig.uniqueBucketName(prefix: "delete")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucket(client, bucket) } }

        let key = "to-delete.txt"
        _ = try await client.putObject(bucket: bucket, key: key, data: Data("delete me".utf8))

        // Verify it exists
        let beforeDelete = try await client.listObjects(bucket: bucket)
        #expect(beforeDelete.objects.contains { $0.key == key })

        // Delete it
        try await client.deleteObject(bucket: bucket, key: key)

        // Verify it's gone
        let afterDelete = try await client.listObjects(bucket: bucket)
        #expect(!afterDelete.objects.contains { $0.key == key })
    }

    @Test
    func copyObject() async throws {
        let client = TestConfig.createClient()
        let bucket = TestConfig.uniqueBucketName(prefix: "copy")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucket(client, bucket) } }

        let sourceKey = "source.txt"
        let destKey = "destination.txt"
        let content = "copy this content"

        _ = try await client.putObject(bucket: bucket, key: sourceKey, data: Data(content.utf8))

        // Copy within same bucket
        _ = try await client.copyObject(
            sourceBucket: bucket,
            sourceKey: sourceKey,
            destinationBucket: bucket,
            destinationKey: destKey
        )

        // Verify copy exists with same content
        let (data, _) = try await client.getObject(bucket: bucket, key: destKey)
        #expect(String(data: data, encoding: .utf8) == content)
    }

    @Test
    func downloadObjectToFile() async throws {
        let client = TestConfig.createClient()
        let bucket = TestConfig.uniqueBucketName(prefix: "download")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucket(client, bucket) } }

        let key = "download-test.bin"
        let content = randomData(size: 1024)
        _ = try await client.putObject(bucket: bucket, key: key, data: content)

        // Download to temp file
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("download-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let metadata = try await client.downloadObject(bucket: bucket, key: key, to: tempFile)

        // Verify file contents
        let downloadedData = try Data(contentsOf: tempFile)
        #expect(downloadedData == content)
        #expect(metadata.contentLength == Int64(content.count))
    }

    @Test
    func downloadObjectWithProgress() async throws {
        let client = TestConfig.createClient()
        let bucket = TestConfig.uniqueBucketName(prefix: "progress")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucket(client, bucket) } }

        let key = "progress-test.bin"
        let content = randomData(size: 10_000) // 10KB
        _ = try await client.putObject(bucket: bucket, key: key, data: content)

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("progress-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        // Download with progress callback - just verify it doesn't throw
        let metadata = try await client.downloadObject(
            bucket: bucket,
            key: key,
            to: tempFile,
            progress: { _, _ in
                // Progress callback - no-op
            }
        )

        // Verify download completed successfully
        let downloadedData = try Data(contentsOf: tempFile)
        #expect(downloadedData == content)
        #expect(metadata.contentLength == Int64(content.count))
    }

    @Test
    func getObjectRange() async throws {
        let client = TestConfig.createClient()
        let bucket = TestConfig.uniqueBucketName(prefix: "range")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucket(client, bucket) } }

        let content = "0123456789ABCDEF"
        _ = try await client.putObject(bucket: bucket, key: "range.txt", data: Data(content.utf8))

        // Get bytes 5-9 (should be "56789")
        let (data, _) = try await client.getObject(bucket: bucket, key: "range.txt", range: 5..<10)
        #expect(String(data: data, encoding: .utf8) == "56789")
    }
}
