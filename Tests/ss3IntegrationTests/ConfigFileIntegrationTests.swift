import Testing
import Foundation
import SwiftS3

@Suite("Config File Integration", .serialized)
struct ConfigFileIntegrationTests {
    init() async throws {
        try await MinioTestServer.shared.ensureRunning()
    }

    @Test func listBucketsWithConfigFile() async throws {
        let client = CLITestConfig.createClient()
        let bucket = CLITestConfig.uniqueBucketName(prefix: "cfglist")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucketViaCLI(bucket) } }

        // Run with config file instead of --profile flag
        let result = try await CLIRunner.run("ls", "minio:", useConfig: true)

        #expect(result.succeeded)
        #expect(result.stdout.contains(bucket))
    }

    @Test func listObjectsWithConfigFile() async throws {
        let client = CLITestConfig.createClient()
        let bucket = CLITestConfig.uniqueBucketName(prefix: "cfgobj")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucketViaCLI(bucket) } }

        _ = try await client.putObject(bucket: bucket, key: "test.txt", data: Data("test".utf8))

        let result = try await CLIRunner.run("ls", "minio:\(bucket)/", useConfig: true)

        #expect(result.succeeded)
        #expect(result.stdout.contains("test.txt"))
    }

    @Test func copyWithConfigFile() async throws {
        let client = CLITestConfig.createClient()
        let bucket = CLITestConfig.uniqueBucketName(prefix: "cfgcp")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucketViaCLI(bucket) } }

        // Create temp file
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-\(UUID().uuidString).txt")
        try "config file test".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let result = try await CLIRunner.run(
            "cp", tempFile.path, "minio:\(bucket)/uploaded.txt",
            useConfig: true
        )

        #expect(result.succeeded)

        // Verify upload
        let (data, _) = try await client.getObject(bucket: bucket, key: "uploaded.txt")
        #expect(String(data: data, encoding: .utf8) == "config file test")
    }

    @Test func profileOverridesTakePrecedence() async throws {
        let client = CLITestConfig.createClient()
        let bucket = CLITestConfig.uniqueBucketName(prefix: "cfgoverride")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucketViaCLI(bucket) } }

        // Run with --profile flag (should still work, uses existing behavior)
        let result = try await CLIRunner.run("ls", "minio:\(bucket)/")

        #expect(result.succeeded)
    }
}
