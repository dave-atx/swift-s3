import Testing
import Foundation
import SwiftS3

@Suite("ss3 ls Command", .serialized)
struct ListTests {
    init() async throws {
        try await MinioTestServer.shared.ensureRunning()
    }

    @Test func listBucketsHumanFormat() async throws {
        try await withTestBucket(prefix: "lsbucket") { _, bucket in
            let result = try await CLIRunner.run("ls")

            #expect(result.succeeded)
            #expect(result.stdout.contains(bucket))
            // Human format shows bucket names and a summary line with "bucket" or "buckets"
            #expect(result.stdout.contains("bucket"))
        }
    }

    @Test func listBucketsJSONFormat() async throws {
        try await withTestBucket(prefix: "lsjson") { _, bucket in
            let result = try await CLIRunner.run("ls", "--format", "json")

            #expect(result.succeeded)
            #expect(result.stdout.contains(bucket))
            #expect(result.stdout.hasPrefix("[")) // JSON array
        }
    }

    @Test func listBucketsTSVFormat() async throws {
        try await withTestBucket(prefix: "lstsv") { _, bucket in
            let result = try await CLIRunner.run("ls", "--format", "tsv")

            #expect(result.succeeded)
            #expect(result.stdout.contains(bucket))
            #expect(result.stdout.contains("\t")) // TSV has tabs
        }
    }

    @Test func listObjectsInBucket() async throws {
        try await withTestBucket(prefix: "lsobj") { client, bucket in
            // Upload test objects
            _ = try await client.putObject(bucket: bucket, key: "file1.txt", data: Data("content1".utf8))
            _ = try await client.putObject(bucket: bucket, key: "file2.txt", data: Data("content2".utf8))

            let result = try await CLIRunner.run("ls", "minio:\(bucket)/")

            #expect(result.succeeded)
            #expect(result.stdout.contains("file1.txt"))
            #expect(result.stdout.contains("file2.txt"))
        }
    }

    @Test func listObjectsWithPrefix() async throws {
        try await withTestBucket(prefix: "lsprefix") { client, bucket in
            // Upload objects with different prefixes
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
            // Upload objects in folder structure
            _ = try await client.putObject(bucket: bucket, key: "folder1/file.txt", data: Data("f1".utf8))
            _ = try await client.putObject(bucket: bucket, key: "folder2/file.txt", data: Data("f2".utf8))

            let result = try await CLIRunner.run("ls", "minio:\(bucket)/")

            #expect(result.succeeded)
            #expect(result.stdout.contains("folder1/"))
            #expect(result.stdout.contains("folder2/"))
        }
    }

    @Test func listObjectsJSONFormat() async throws {
        try await withTestBucket(prefix: "lsobjjson") { client, bucket in
            _ = try await client.putObject(bucket: bucket, key: "test.txt", data: Data("test".utf8))

            let result = try await CLIRunner.run("ls", "minio:\(bucket)/", "--format", "json")

            #expect(result.succeeded)
            #expect(result.stdout.contains("test.txt"))
            #expect(result.stdout.contains("\"key\"")) // JSON field
        }
    }

    @Test func listNonexistentBucketFails() async throws {
        let result = try await CLIRunner.run("ls", "minio:nonexistent-bucket-xyz123/")

        #expect(!result.succeeded)
        #expect(result.exitCode == 1)
    }
}
