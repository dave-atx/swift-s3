import Testing
import Foundation
import SwiftS3

@Suite("ss3 rm Command", .serialized)
struct RemoveTests {
    init() async throws {
        try await MinioTestServer.shared.ensureRunning()
    }

    @Test("Remove existing file succeeds")
    func removeExistingFile() async throws {
        try await withTestBucket(prefix: "rmok") { client, bucket in
            // Create a file via library
            let content = "File to delete"
            _ = try await client.putObject(bucket: bucket, key: "delete-me.txt", data: Data(content.utf8))

            // Delete via CLI
            let result = try await CLIRunner.run("rm", "minio:\(bucket)/delete-me.txt")

            #expect(result.succeeded)
            #expect(result.stdout.contains("Deleted"))

            // Verify file is gone
            do {
                _ = try await client.headObject(bucket: bucket, key: "delete-me.txt")
                Issue.record("Expected file to be deleted")
            } catch {
                // Expected - file should not exist
            }
        }
    }

    @Test("Remove nonexistent file succeeds")
    func removeNonexistentFile() async throws {
        try await withTestBucket(prefix: "rmfail") { _, bucket in
            let result = try await CLIRunner.run("rm", "minio:\(bucket)/nonexistent.txt")

            // S3 delete is idempotent, succeeds even for nonexistent objects
            #expect(result.succeeded)
            #expect(result.exitCode == 0)
        }
    }

    @Test("Remove directory path fails")
    func removeDirectoryPathFails() async throws {
        try await withTestBucket(prefix: "rmdir") { _, bucket in
            // Path ending with / should be rejected by validation
            let result = try await CLIRunner.run("rm", "minio:\(bucket)/somedir/")

            #expect(!result.succeeded)
            // ArgumentParser's ValidationError exits with code 64
            #expect(result.exitCode == 64)
        }
    }

    @Test("Remove without key fails")
    func removeWithoutKeyFails() async throws {
        try await withTestBucket(prefix: "rmnokey") { _, bucket in
            // Just bucket, no key
            let result = try await CLIRunner.run("rm", "minio:\(bucket)")

            #expect(!result.succeeded)
            #expect(result.exitCode == 64)
        }
    }

    @Test("Remove local path fails")
    func removeLocalPathFails() async throws {
        let result = try await CLIRunner.run("rm", "/tmp/somefile.txt")

        #expect(!result.succeeded)
        #expect(result.exitCode == 64)
    }

    @Test("Remove nested key succeeds")
    func removeNestedKey() async throws {
        try await withTestBucket(prefix: "rmnest") { client, bucket in
            // Create nested file
            _ = try await client.putObject(
                bucket: bucket,
                key: "deep/nested/path/file.txt",
                data: Data("nested content".utf8)
            )

            // Delete via CLI
            let result = try await CLIRunner.run("rm", "minio:\(bucket)/deep/nested/path/file.txt")

            #expect(result.succeeded)
        }
    }
}
