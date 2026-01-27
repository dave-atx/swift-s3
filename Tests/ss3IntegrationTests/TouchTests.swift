import Testing
import Foundation
import SwiftS3

@Suite("ss3 touch Command", .serialized)
struct TouchTests {
    init() async throws {
        try await MinioTestServer.shared.ensureRunning()
    }

    @Test("Touch creates empty file")
    func touchCreatesEmptyFile() async throws {
        try await withTestBucket(prefix: "touchok") { client, bucket in
            // Create via CLI
            let result = try await CLIRunner.run("touch", "minio:\(bucket)/newfile.txt")

            #expect(result.succeeded)
            #expect(result.stdout.contains("Created"))

            // Verify file exists and is empty
            let (data, metadata) = try await client.getObject(bucket: bucket, key: "newfile.txt")
            #expect(data.isEmpty)
            #expect(metadata.contentLength == 0)
        }
    }

    @Test("Touch existing file fails")
    func touchExistingFileFails() async throws {
        try await withTestBucket(prefix: "touchexist") { client, bucket in
            // Create a file first
            _ = try await client.putObject(bucket: bucket, key: "existing.txt", data: Data("content".utf8))

            // Try to touch it - should fail
            let result = try await CLIRunner.run("touch", "minio:\(bucket)/existing.txt")

            #expect(!result.succeeded)
            #expect(result.exitCode == 1)
            #expect(result.stderr.contains("already exists"))
        }
    }

    @Test("Touch directory path fails")
    func touchDirectoryPathFails() async throws {
        try await withTestBucket(prefix: "touchdir") { _, bucket in
            let result = try await CLIRunner.run("touch", "minio:\(bucket)/somedir/")

            #expect(!result.succeeded)
            #expect(result.exitCode == 64)
        }
    }

    @Test("Touch without key fails")
    func touchWithoutKeyFails() async throws {
        try await withTestBucket(prefix: "touchnokey") { _, bucket in
            let result = try await CLIRunner.run("touch", "minio:\(bucket)")

            #expect(!result.succeeded)
            #expect(result.exitCode == 64)
        }
    }

    @Test("Touch local path fails")
    func touchLocalPathFails() async throws {
        let result = try await CLIRunner.run("touch", "/tmp/somefile.txt")

        #expect(!result.succeeded)
        #expect(result.exitCode == 64)
    }

    @Test("Touch nested path creates file")
    func touchNestedPath() async throws {
        try await withTestBucket(prefix: "touchnest") { client, bucket in
            let result = try await CLIRunner.run("touch", "minio:\(bucket)/deep/nested/path/file.txt")

            #expect(result.succeeded)

            // Verify file exists
            let (data, _) = try await client.getObject(bucket: bucket, key: "deep/nested/path/file.txt")
            #expect(data.isEmpty)
        }
    }
}
