import Testing
import Foundation
import SwiftS3

@Suite("ss3 mv Command", .serialized)
struct MoveTests {
    init() async throws {
        try await MinioTestServer.shared.ensureRunning()
    }

    @Test("Move file within same bucket")
    func moveWithinBucket() async throws {
        try await withTestBucket(prefix: "mvsame") { client, bucket in
            // Create source file
            let content = "Content to move"
            _ = try await client.putObject(bucket: bucket, key: "source.txt", data: Data(content.utf8))

            // Move via CLI
            let result = try await CLIRunner.run(
                "mv",
                "minio:\(bucket)/source.txt",
                "minio:\(bucket)/dest.txt"
            )

            #expect(result.succeeded)
            #expect(result.stdout.contains("Moved"))

            // Verify source is gone
            do {
                _ = try await client.headObject(bucket: bucket, key: "source.txt")
                Issue.record("Source should be deleted")
            } catch {
                // Expected
            }

            // Verify destination exists with correct content
            let (data, _) = try await client.getObject(bucket: bucket, key: "dest.txt")
            #expect(String(data: data, encoding: .utf8) == content)
        }
    }

    @Test("Move file to different bucket")
    func moveToDifferentBucket() async throws {
        let client = CLITestConfig.createClient()
        let srcBucket = CLITestConfig.uniqueBucketName(prefix: "mvsrc")
        let dstBucket = CLITestConfig.uniqueBucketName(prefix: "mvdst")

        try await client.createBucket(srcBucket)
        try await client.createBucket(dstBucket)

        defer {
            Task {
                await cleanupBucket(srcBucket)
                await cleanupBucket(dstBucket)
            }
        }

        // Create source file
        let content = "Cross-bucket move"
        _ = try await client.putObject(bucket: srcBucket, key: "file.txt", data: Data(content.utf8))

        // Move via CLI
        let result = try await CLIRunner.run(
            "mv",
            "minio:\(srcBucket)/file.txt",
            "minio:\(dstBucket)/file.txt"
        )

        #expect(result.succeeded)

        // Verify source is gone
        do {
            _ = try await client.headObject(bucket: srcBucket, key: "file.txt")
            Issue.record("Source should be deleted")
        } catch {
            // Expected
        }

        // Verify destination exists
        let (data, _) = try await client.getObject(bucket: dstBucket, key: "file.txt")
        #expect(String(data: data, encoding: .utf8) == content)
    }

    @Test("Move nonexistent file fails")
    func moveNonexistentFails() async throws {
        try await withTestBucket(prefix: "mvfail") { _, bucket in
            let result = try await CLIRunner.run(
                "mv",
                "minio:\(bucket)/nonexistent.txt",
                "minio:\(bucket)/dest.txt"
            )

            #expect(!result.succeeded)
            #expect(result.exitCode == 1)
        }
    }

    @Test("Move overwrites existing destination")
    func moveOverwritesDestination() async throws {
        try await withTestBucket(prefix: "mvover") { client, bucket in
            // Create source and destination files
            let srcContent = "Source content"
            let dstContent = "Destination content"
            _ = try await client.putObject(bucket: bucket, key: "source.txt", data: Data(srcContent.utf8))
            _ = try await client.putObject(bucket: bucket, key: "dest.txt", data: Data(dstContent.utf8))

            // Move (should overwrite)
            let result = try await CLIRunner.run(
                "mv",
                "minio:\(bucket)/source.txt",
                "minio:\(bucket)/dest.txt"
            )

            #expect(result.succeeded)

            // Verify destination has source content
            let (data, _) = try await client.getObject(bucket: bucket, key: "dest.txt")
            #expect(String(data: data, encoding: .utf8) == srcContent)
        }
    }

    @Test("Move directory path fails")
    func moveDirectoryPathFails() async throws {
        try await withTestBucket(prefix: "mvdir") { _, bucket in
            let result = try await CLIRunner.run(
                "mv",
                "minio:\(bucket)/dir/",
                "minio:\(bucket)/dest/"
            )

            #expect(!result.succeeded)
            #expect(result.exitCode == 64)
        }
    }

    @Test("Move local source fails")
    func moveLocalSourceFails() async throws {
        try await withTestBucket(prefix: "mvlocal") { _, bucket in
            let result = try await CLIRunner.run(
                "mv",
                "/tmp/local.txt",
                "minio:\(bucket)/dest.txt"
            )

            #expect(!result.succeeded)
            #expect(result.exitCode == 64)
        }
    }

    @Test("Move to local destination fails")
    func moveToLocalDestinationFails() async throws {
        try await withTestBucket(prefix: "mvlocal2") { client, bucket in
            _ = try await client.putObject(bucket: bucket, key: "source.txt", data: Data("content".utf8))

            let result = try await CLIRunner.run(
                "mv",
                "minio:\(bucket)/source.txt",
                "/tmp/local.txt"
            )

            #expect(!result.succeeded)
            #expect(result.exitCode == 64)
        }
    }

    @Test("Move nested key succeeds")
    func moveNestedKey() async throws {
        try await withTestBucket(prefix: "mvnest") { client, bucket in
            // Create nested source
            _ = try await client.putObject(
                bucket: bucket,
                key: "deep/nested/source.txt",
                data: Data("nested".utf8)
            )

            // Move to different nested path
            let result = try await CLIRunner.run(
                "mv",
                "minio:\(bucket)/deep/nested/source.txt",
                "minio:\(bucket)/other/path/dest.txt"
            )

            #expect(result.succeeded)

            // Verify move worked
            let (data, _) = try await client.getObject(bucket: bucket, key: "other/path/dest.txt")
            #expect(String(data: data, encoding: .utf8) == "nested")
        }
    }
}
