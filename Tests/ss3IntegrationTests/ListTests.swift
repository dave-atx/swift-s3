import Testing
import Foundation
import SwiftS3

@Suite("ss3 ls Command", .serialized)
struct ListTests {
    init() async throws {
        try await MinioTestServer.shared.ensureRunning()
    }

    @Test func listBucketsDefault() async throws {
        try await withTestBucket(prefix: "lsbucket") { _, bucket in
            let result = try await CLIRunner.run("ls")

            #expect(result.succeeded)
            #expect(result.stdout.contains(bucket))
            // Default format: just bucket names, no summary line
        }
    }

    @Test func listBucketsLongFormat() async throws {
        try await withTestBucket(prefix: "lslong") { _, bucket in
            let result = try await CLIRunner.run("ls", "-l")

            #expect(result.succeeded)
            #expect(result.stdout.contains(bucket))
            // Long format shows date before bucket name
        }
    }

    @Test func listBucketsHumanFlag() async throws {
        try await withTestBucket(prefix: "lshuman") { _, bucket in
            let result = try await CLIRunner.run("ls", "-h")

            #expect(result.succeeded)
            #expect(result.stdout.contains(bucket))
            // -h is synonym for -l
        }
    }

    @Test func listObjectsDefault() async throws {
        try await withTestBucket(prefix: "lsobj") { client, bucket in
            _ = try await client.putObject(bucket: bucket, key: "file1.txt", data: Data("content1".utf8))
            _ = try await client.putObject(bucket: bucket, key: "file2.txt", data: Data("content2".utf8))

            let result = try await CLIRunner.run("ls", "minio:\(bucket)/")

            #expect(result.succeeded)
            let lines = result.stdout.split(separator: "\n").map(String.init)
            // Default: just filenames, one per line
            #expect(lines.contains("file1.txt"))
            #expect(lines.contains("file2.txt"))
        }
    }

    @Test func listObjectsLongFormat() async throws {
        try await withTestBucket(prefix: "lsobjlong") { client, bucket in
            _ = try await client.putObject(bucket: bucket, key: "test.txt", data: Data("test content".utf8))

            let result = try await CLIRunner.run("ls", "-l", "minio:\(bucket)/")

            #expect(result.succeeded)
            #expect(result.stdout.contains("test.txt"))
            // Long format includes size
            #expect(result.stdout.contains("B") || result.stdout.contains("K"))
        }
    }

    @Test func listObjectsWithPrefix() async throws {
        try await withTestBucket(prefix: "lsprefix") { client, bucket in
            _ = try await client.putObject(bucket: bucket, key: "docs/readme.txt", data: Data("readme".utf8))
            _ = try await client.putObject(bucket: bucket, key: "docs/guide.txt", data: Data("guide".utf8))
            _ = try await client.putObject(bucket: bucket, key: "images/logo.png", data: Data("logo".utf8))

            let result = try await CLIRunner.run("ls", "minio:\(bucket)/docs/")

            #expect(result.succeeded)
            #expect(result.stdout.contains("readme.txt"))
            #expect(result.stdout.contains("guide.txt"))
            #expect(!result.stdout.contains("logo.png"))
        }
    }

    @Test func listObjectsShowsFolders() async throws {
        try await withTestBucket(prefix: "lsfolder") { client, bucket in
            _ = try await client.putObject(bucket: bucket, key: "folder1/file.txt", data: Data("f1".utf8))
            _ = try await client.putObject(bucket: bucket, key: "folder2/file.txt", data: Data("f2".utf8))

            let result = try await CLIRunner.run("ls", "minio:\(bucket)/")

            #expect(result.succeeded)
            #expect(result.stdout.contains("folder1/"))
            #expect(result.stdout.contains("folder2/"))
        }
    }

    @Test func listObjectsSortByTime() async throws {
        try await withTestBucket(prefix: "lstime") { client, bucket in
            // Upload files with slight delay to ensure different timestamps
            _ = try await client.putObject(bucket: bucket, key: "older.txt", data: Data("old".utf8))
            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
            _ = try await client.putObject(bucket: bucket, key: "newer.txt", data: Data("new".utf8))

            let result = try await CLIRunner.run("ls", "-t", "minio:\(bucket)/")

            #expect(result.succeeded)
            let lines = result.stdout.split(separator: "\n").map(String.init)
            // Most recent first
            guard let newerIndex = lines.firstIndex(of: "newer.txt"),
                  let olderIndex = lines.firstIndex(of: "older.txt") else {
                Issue.record("Expected both newer.txt and older.txt in output")
                return
            }
            #expect(newerIndex < olderIndex)
        }
    }

    @Test func listObjectsCombinedFlags() async throws {
        try await withTestBucket(prefix: "lscombined") { client, bucket in
            _ = try await client.putObject(bucket: bucket, key: "file.txt", data: Data("content".utf8))

            let result = try await CLIRunner.run("ls", "-lt", "minio:\(bucket)/")

            #expect(result.succeeded)
            #expect(result.stdout.contains("file.txt"))
            // Should have size in output (long format)
            #expect(result.stdout.contains("B") || result.stdout.contains("K"))
        }
    }

    @Test func listNonexistentBucketFails() async throws {
        let result = try await CLIRunner.run("ls", "minio:nonexistent-bucket-xyz123/")

        #expect(!result.succeeded)
        #expect(result.exitCode == 1)
    }
}
