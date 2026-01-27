import Testing
import Foundation
import SwiftS3

@Suite("ss3 cp Command", .serialized)
struct CopyTests {
    init() async throws {
        try await MinioTestServer.shared.ensureRunning()
    }

    @Test("Upload small file")
    func uploadSmallFile() async throws {
        try await withTestBucket(prefix: "cpup") { client, bucket in
            // Create temp file
            let tempFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("upload-test-\(UUID().uuidString).txt")
            let content = "Hello from CLI upload test!"
            try content.write(to: tempFile, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: tempFile) }

            // Upload via CLI
            let result = try await CLIRunner.run("cp", tempFile.path, "minio:\(bucket)/uploaded.txt")

            #expect(result.succeeded)

            // Verify via library
            let (data, _) = try await client.getObject(bucket: bucket, key: "uploaded.txt")
            #expect(String(data: data, encoding: .utf8) == content)
        }
    }

    @Test("Upload to key with trailing slash")
    func uploadToKeyWithTrailingSlash() async throws {
        try await withTestBucket(prefix: "cpslash") { client, bucket in
            // Create temp file
            let tempFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("slash-test-\(UUID().uuidString).txt")
            let content = "Test trailing slash"
            try content.write(to: tempFile, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: tempFile) }

            let fileName = (tempFile.path as NSString).lastPathComponent

            // Upload with trailing slash - should use filename
            let result = try await CLIRunner.run("cp", tempFile.path, "minio:\(bucket)/prefix/")

            #expect(result.succeeded)

            // Verify the file was uploaded with correct key
            let (data, _) = try await client.getObject(bucket: bucket, key: "prefix/\(fileName)")
            #expect(String(data: data, encoding: .utf8) == content)
        }
    }

    @Test("Download file")
    func downloadFile() async throws {
        try await withTestBucket(prefix: "cpdown") { client, bucket in
            // Upload via library
            let content = "Content to download via CLI"
            _ = try await client.putObject(bucket: bucket, key: "download-me.txt", data: Data(content.utf8))

            // Download via CLI
            let tempFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("downloaded-\(UUID().uuidString).txt")
            defer { try? FileManager.default.removeItem(at: tempFile) }

            let result = try await CLIRunner.run("cp", "minio:\(bucket)/download-me.txt", tempFile.path)

            #expect(result.succeeded)

            // Verify downloaded content
            let downloaded = try String(contentsOf: tempFile, encoding: .utf8)
            #expect(downloaded == content)
        }
    }

    @Test("Download to directory")
    func downloadToDirectory() async throws {
        try await withTestBucket(prefix: "cpdir") { client, bucket in
            // Upload via library
            let content = "Download to directory test"
            let key = "test-file.txt"
            _ = try await client.putObject(bucket: bucket, key: key, data: Data(content.utf8))

            // Create temp directory
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("download-dir-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // Download to directory
            let result = try await CLIRunner.run("cp", "minio:\(bucket)/\(key)", tempDir.path)

            #expect(result.succeeded)

            // Verify file exists in directory with correct name
            let downloadedFile = tempDir.appendingPathComponent(key)
            #expect(FileManager.default.fileExists(atPath: downloadedFile.path))

            let downloaded = try String(contentsOf: downloadedFile, encoding: .utf8)
            #expect(downloaded == content)
        }
    }

    @Test("Upload nonexistent file fails")
    func uploadNonexistentFileFails() async throws {
        try await withTestBucket(prefix: "cpfail") { _, bucket in
            let result = try await CLIRunner.run(
                "cp",
                "/nonexistent/file-\(UUID().uuidString).txt",
                "minio:\(bucket)/key"
            )

            #expect(!result.succeeded)
            #expect(result.exitCode == 1)
        }
    }

    @Test("Download nonexistent key fails")
    func downloadNonexistentKeyFails() async throws {
        try await withTestBucket(prefix: "cpnokey") { _, bucket in
            let tempFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("should-not-exist-\(UUID().uuidString).txt")
            defer { try? FileManager.default.removeItem(at: tempFile) }

            let result = try await CLIRunner.run("cp", "minio:\(bucket)/nonexistent-key.txt", tempFile.path)

            #expect(!result.succeeded)
            #expect(result.exitCode == 1)
            // Note: An empty file may be created before the download fails
            // We verify the command failed, not the file existence
        }
    }

    @Test("Copy both local paths fails")
    func copyBothLocalPathsFails() async throws {
        // Create two temp files
        let file1 = FileManager.default.temporaryDirectory
            .appendingPathComponent("file1-\(UUID().uuidString).txt")
        let file2 = FileManager.default.temporaryDirectory
            .appendingPathComponent("file2-\(UUID().uuidString).txt")

        try "file1".write(to: file1, atomically: true, encoding: .utf8)
        try "file2".write(to: file2, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: file1)
            try? FileManager.default.removeItem(at: file2)
        }

        // Attempting to copy two local paths should fail
        let result = try await CLIRunner.run("cp", file1.path, file2.path)

        #expect(!result.succeeded)
        // ArgumentParser's ValidationError exits with code 64
        #expect(result.exitCode == 64)
    }

    @Test("Large file multipart upload")
    func largeFileMultipartUpload() async throws {
        try await withTestBucket(prefix: "cpmulti") { client, bucket in
            // Create a file larger than our multipart threshold
            // AWS/minio require minimum 5MB part size, so use 6MB chunks with 12MB file
            let largeSize: Int64 = 12 * 1024 * 1024  // 12MB
            let tempFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("large-upload-\(UUID().uuidString).bin")

            // Create file with repeating pattern (faster than random)
            let pattern = Data(repeating: 0x42, count: 1024 * 1024)  // 1MB pattern
            var data = Data()
            for _ in 0..<12 {
                data.append(pattern)
            }
            try data.write(to: tempFile)
            defer { try? FileManager.default.removeItem(at: tempFile) }

            // Upload with 10MB threshold and 6MB chunks (2 parts of 6MB each)
            let result = try await CLIRunner.run(
                "cp",
                "--multipart-threshold", "10000000",  // 10MB threshold
                "--chunk-size", "6000000",            // 6MB chunks (>5MB minimum)
                tempFile.path,
                "minio:\(bucket)/large-file.bin"
            )

            #expect(result.succeeded)

            // Verify uploaded file size matches
            let (downloadedData, _) = try await client.getObject(bucket: bucket, key: "large-file.bin")
            #expect(downloadedData.count == Int(largeSize))
        }
    }

    @Test("Custom chunk size and parallel uploads")
    func customChunkSizeAndParallelUploads() async throws {
        try await withTestBucket(prefix: "cppar") { client, bucket in
            // Create a 15MB file (3 parts of 5MB each)
            let size: Int64 = 15 * 1024 * 1024
            let tempFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("parallel-upload-\(UUID().uuidString).bin")

            // Create file with repeating pattern (faster than random)
            let pattern = Data(repeating: 0xAB, count: 1024 * 1024)  // 1MB pattern
            var data = Data()
            for _ in 0..<15 {
                data.append(pattern)
            }
            try data.write(to: tempFile)
            defer { try? FileManager.default.removeItem(at: tempFile) }

            // Upload with custom chunk size (must be >= 5MB) and parallel setting
            let result = try await CLIRunner.run(
                "cp",
                "--multipart-threshold", "10000000",  // 10MB threshold
                "--chunk-size", "5242880",            // 5MB chunks (exactly 5MB minimum)
                "--parallel", "2",                    // 2 parallel uploads
                tempFile.path,
                "minio:\(bucket)/parallel-file.bin"
            )

            #expect(result.succeeded)

            // Verify the upload
            let (downloadedData, _) = try await client.getObject(bucket: bucket, key: "parallel-file.bin")
            #expect(downloadedData.count == Int(size))
        }
    }

    @Test("Upload with nested S3 path")
    func uploadWithNestedS3Path() async throws {
        try await withTestBucket(prefix: "cpnest") { client, bucket in
            let tempFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("nested-test-\(UUID().uuidString).txt")
            let content = "Nested path test"
            try content.write(to: tempFile, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: tempFile) }

            // Upload to nested path
            let result = try await CLIRunner.run(
                "cp",
                tempFile.path,
                "minio:\(bucket)/deep/nested/path/file.txt"
            )

            #expect(result.succeeded)

            // Verify
            let (data, _) = try await client.getObject(
                bucket: bucket,
                key: "deep/nested/path/file.txt"
            )
            #expect(String(data: data, encoding: .utf8) == content)
        }
    }

    @Test("Download with key containing slashes")
    func downloadWithKeyContainingSlashes() async throws {
        try await withTestBucket(prefix: "cpslash2") { client, bucket in
            // Upload via library with key containing slashes
            let content = "File in nested directory"
            let key = "path/to/file.txt"
            _ = try await client.putObject(bucket: bucket, key: key, data: Data(content.utf8))

            let tempFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("download-nested-\(UUID().uuidString).txt")
            defer { try? FileManager.default.removeItem(at: tempFile) }

            // Download
            let result = try await CLIRunner.run("cp", "minio:\(bucket)/\(key)", tempFile.path)

            #expect(result.succeeded)

            let downloaded = try String(contentsOf: tempFile, encoding: .utf8)
            #expect(downloaded == content)
        }
    }
}
