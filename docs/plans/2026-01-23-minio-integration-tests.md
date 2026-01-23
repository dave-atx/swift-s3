# Minio Integration Tests Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add comprehensive integration tests using minio as an S3-compatible server for both the SwiftS3 library and ss3 CLI.

**Architecture:** Standalone minio binary downloaded via setup script, managed by `MinioTestServer` actor that starts/stops the server per test suite. Each test creates isolated buckets with UUID suffixes for parallelism safety. CLI tests execute the built `ss3` binary and verify stdout/stderr.

**Tech Stack:** Swift Testing framework, minio server binary, Process for CLI execution, Foundation networking.

---

## Task 1: Add .minio/ to .gitignore

**Files:**
- Modify: `.gitignore`

**Step 1: Add minio directory to gitignore**

Add at the end of `.gitignore`:

```
# Minio binary (downloaded by setup script)
.minio/
```

**Step 2: Verify change**

Run: `grep -n "minio" .gitignore`
Expected: Line showing `.minio/`

**Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: add .minio/ to gitignore for integration tests"
```

---

## Task 2: Create setup-minio.sh script

**Files:**
- Create: `Scripts/setup-minio.sh`

**Step 1: Create the Scripts directory and setup script**

```bash
#!/bin/bash
set -euo pipefail

# Detect platform and architecture
OS=$(uname -s)
ARCH=$(uname -m)

# Map to minio download names
case "$OS" in
    Darwin)
        case "$ARCH" in
            arm64) MINIO_BINARY="minio-darwin-arm64" ;;
            x86_64) MINIO_BINARY="minio-darwin-amd64" ;;
            *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
        esac
        ;;
    Linux)
        case "$ARCH" in
            x86_64) MINIO_BINARY="minio-linux-amd64" ;;
            aarch64) MINIO_BINARY="minio-linux-arm64" ;;
            *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
        esac
        ;;
    *)
        echo "Unsupported OS: $OS"
        exit 1
        ;;
esac

# Setup paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MINIO_DIR="$PROJECT_DIR/.minio"
MINIO_PATH="$MINIO_DIR/minio"

# Check if already exists
if [ -f "$MINIO_PATH" ]; then
    echo "minio already installed at $MINIO_PATH"
    "$MINIO_PATH" --version
    exit 0
fi

# Create directory
mkdir -p "$MINIO_DIR"

# Download minio
DOWNLOAD_URL="https://dl.min.io/server/minio/release/${OS,,}/${ARCH,,}/minio"
# Use platform-specific URL format
case "$OS" in
    Darwin)
        case "$ARCH" in
            arm64) DOWNLOAD_URL="https://dl.min.io/server/minio/release/darwin-arm64/minio" ;;
            x86_64) DOWNLOAD_URL="https://dl.min.io/server/minio/release/darwin-amd64/minio" ;;
        esac
        ;;
    Linux)
        case "$ARCH" in
            x86_64) DOWNLOAD_URL="https://dl.min.io/server/minio/release/linux-amd64/minio" ;;
            aarch64) DOWNLOAD_URL="https://dl.min.io/server/minio/release/linux-arm64/minio" ;;
        esac
        ;;
esac

echo "Downloading minio from $DOWNLOAD_URL..."
curl -fSL "$DOWNLOAD_URL" -o "$MINIO_PATH"
chmod +x "$MINIO_PATH"

echo "minio installed successfully"
"$MINIO_PATH" --version
```

**Step 2: Make script executable**

Run: `chmod +x Scripts/setup-minio.sh`

**Step 3: Run script to verify it works**

Run: `./Scripts/setup-minio.sh`
Expected: Downloads minio binary, shows version

**Step 4: Verify minio binary exists**

Run: `ls -la .minio/minio`
Expected: Executable file exists

**Step 5: Commit**

```bash
git add Scripts/setup-minio.sh
git commit -m "feat: add setup-minio.sh script for integration tests"
```

---

## Task 3: Add IntegrationTests target to Package.swift

**Files:**
- Modify: `Package.swift`

**Step 1: Add IntegrationTests test target**

Add after the existing `ss3Tests` target:

```swift
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["SwiftS3"]
        ),
        .testTarget(
            name: "ss3IntegrationTests",
            dependencies: ["ss3"]
        )
```

**Step 2: Verify Package.swift is valid**

Run: `swift package describe`
Expected: Shows all 4 test targets including IntegrationTests and ss3IntegrationTests

**Step 3: Commit**

```bash
git add Package.swift
git commit -m "feat: add IntegrationTests and ss3IntegrationTests targets"
```

---

## Task 4: Create MinioTestServer actor

**Files:**
- Create: `Tests/IntegrationTests/MinioTestServer.swift`

**Step 1: Create the MinioTestServer file**

```swift
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Manages a minio server process for integration testing.
/// Call `ensureRunning()` before tests and `stop()` after.
actor MinioTestServer {
    static let shared = MinioTestServer()

    static let port = 9199
    static let accessKey = "minioadmin"
    static let secretKey = "minioadmin"
    static let endpoint = "http://127.0.0.1:\(port)"

    private var process: Process?
    private var dataDirectory: URL?
    private var isRunning = false

    private init() {}

    /// Ensures the minio server is running. Safe to call multiple times.
    func ensureRunning() async throws {
        if isRunning {
            return
        }

        let minioBinary = findMinioBinary()
        guard FileManager.default.fileExists(atPath: minioBinary) else {
            throw MinioError.binaryNotFound(
                "minio binary not found at \(minioBinary). Run ./Scripts/setup-minio.sh first."
            )
        }

        // Create temp data directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("minio-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        dataDirectory = tempDir

        // Start minio process
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: minioBinary)
        proc.arguments = ["server", tempDir.path, "--address", ":\(Self.port)"]
        proc.environment = [
            "MINIO_ROOT_USER": Self.accessKey,
            "MINIO_ROOT_PASSWORD": Self.secretKey
        ]

        // Suppress output
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        try proc.run()
        process = proc
        isRunning = true

        // Wait for server to be ready
        try await waitForReady()
    }

    /// Stops the minio server and cleans up data directory.
    func stop() async {
        if let proc = process, proc.isRunning {
            proc.terminate()
            proc.waitUntilExit()
        }
        process = nil
        isRunning = false

        // Clean up data directory
        if let dataDir = dataDirectory {
            try? FileManager.default.removeItem(at: dataDir)
        }
        dataDirectory = nil
    }

    /// Polls the minio health endpoint until the server is ready.
    private func waitForReady() async throws {
        let healthURL = URL(string: "\(Self.endpoint)/minio/health/live")!
        let maxAttempts = 30
        let delayNanoseconds: UInt64 = 100_000_000 // 100ms

        for attempt in 1...maxAttempts {
            do {
                let (_, response) = try await URLSession.shared.data(from: healthURL)
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200 {
                    return
                }
            } catch {
                // Server not ready yet
            }

            if attempt == maxAttempts {
                throw MinioError.serverNotReady("minio server did not become ready after \(maxAttempts) attempts")
            }

            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
    }

    private func findMinioBinary() -> String {
        // Look relative to the test file location
        // Tests run from the package root, so .minio/minio should work
        let possiblePaths = [
            ".minio/minio",
            "../.minio/minio",
            "../../.minio/minio"
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Fall back to absolute path from current directory
        let cwd = FileManager.default.currentDirectoryPath
        return "\(cwd)/.minio/minio"
    }
}

enum MinioError: Error, CustomStringConvertible {
    case binaryNotFound(String)
    case serverNotReady(String)

    var description: String {
        switch self {
        case .binaryNotFound(let msg): return msg
        case .serverNotReady(let msg): return msg
        }
    }
}
```

**Step 2: Verify file compiles**

Run: `swift build --target IntegrationTests 2>&1 | head -20`
Expected: Builds without errors (or only warnings about no tests yet)

**Step 3: Commit**

```bash
git add Tests/IntegrationTests/MinioTestServer.swift
git commit -m "feat: add MinioTestServer actor for managing minio process"
```

---

## Task 5: Create TestHelpers with S3 test configuration

**Files:**
- Create: `Tests/IntegrationTests/TestHelpers.swift`

**Step 1: Create TestHelpers file**

```swift
import Foundation
import SwiftS3

/// Shared test configuration and utilities for integration tests.
enum TestConfig {
    static var s3Configuration: S3Configuration {
        S3Configuration(
            accessKeyId: MinioTestServer.accessKey,
            secretAccessKey: MinioTestServer.secretKey,
            region: "us-east-1",
            endpoint: URL(string: MinioTestServer.endpoint)!,
            usePathStyle: true
        )
    }

    static func createClient() -> S3Client {
        S3Client(configuration: s3Configuration)
    }

    /// Generates a unique bucket name for test isolation.
    static func uniqueBucketName(prefix: String = "test") -> String {
        let uuid = UUID().uuidString.prefix(8).lowercased()
        return "\(prefix)-\(uuid)"
    }
}

/// Cleans up a bucket by deleting all objects then the bucket itself.
/// Silently ignores errors to avoid masking test failures.
func cleanupBucket(_ client: S3Client, _ bucketName: String) async {
    do {
        // List and delete all objects
        let result = try await client.listObjects(bucket: bucketName)
        for object in result.objects {
            try? await client.deleteObject(bucket: bucketName, key: object.key)
        }

        // Delete the bucket
        try await client.deleteBucket(bucketName)
    } catch {
        // Ignore cleanup errors
    }
}

/// Generates random data of specified size for testing.
func randomData(size: Int) -> Data {
    var data = Data(count: size)
    for i in 0..<size {
        data[i] = UInt8.random(in: 0...255)
    }
    return data
}
```

**Step 2: Verify file compiles**

Run: `swift build --target IntegrationTests 2>&1 | head -20`
Expected: Builds without errors

**Step 3: Commit**

```bash
git add Tests/IntegrationTests/TestHelpers.swift
git commit -m "feat: add TestHelpers with S3 configuration for integration tests"
```

---

## Task 6: Create BucketTests

**Files:**
- Create: `Tests/IntegrationTests/BucketTests.swift`

**Step 1: Write the bucket integration tests**

```swift
import Testing
import Foundation
@testable import SwiftS3

@Suite("Bucket Operations", .serialized)
struct BucketTests {
    init() async throws {
        try await MinioTestServer.shared.ensureRunning()
    }

    @Test func createAndDeleteBucket() async throws {
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

    @Test func listBuckets() async throws {
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

    @Test func deleteBucketThatDoesNotExist() async throws {
        let client = TestConfig.createClient()
        let bucketName = "nonexistent-bucket-\(UUID().uuidString.prefix(8).lowercased())"

        // Attempting to delete non-existent bucket should throw
        await #expect(throws: (any Error).self) {
            try await client.deleteBucket(bucketName)
        }
    }

    @Test func createDuplicateBucket() async throws {
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
```

**Step 2: Run the bucket tests**

Run: `./Scripts/setup-minio.sh && swift test --filter IntegrationTests.BucketTests 2>&1 | tail -20`
Expected: All bucket tests pass

**Step 3: Commit**

```bash
git add Tests/IntegrationTests/BucketTests.swift
git commit -m "feat: add bucket integration tests"
```

---

## Task 7: Create ObjectTests

**Files:**
- Create: `Tests/IntegrationTests/ObjectTests.swift`

**Step 1: Write the object integration tests**

```swift
import Testing
import Foundation
@testable import SwiftS3

@Suite("Object Operations", .serialized)
struct ObjectTests {
    init() async throws {
        try await MinioTestServer.shared.ensureRunning()
    }

    @Test func putAndGetObject() async throws {
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

    @Test func putObjectWithMetadata() async throws {
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

    @Test func listObjects() async throws {
        let client = TestConfig.createClient()
        let bucket = TestConfig.uniqueBucketName(prefix: "listobj")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucket(client, bucket) } }

        // Upload multiple objects
        for i in 1...3 {
            let data = Data("content \(i)".utf8)
            _ = try await client.putObject(bucket: bucket, key: "file\(i).txt", data: data)
        }

        // List objects
        let result = try await client.listObjects(bucket: bucket)
        #expect(result.objects.count == 3)
        #expect(result.objects.contains { $0.key == "file1.txt" })
        #expect(result.objects.contains { $0.key == "file2.txt" })
        #expect(result.objects.contains { $0.key == "file3.txt" })
    }

    @Test func listObjectsWithPrefix() async throws {
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

    @Test func listObjectsWithDelimiter() async throws {
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

    @Test func headObject() async throws {
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

    @Test func deleteObject() async throws {
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

    @Test func copyObject() async throws {
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

    @Test func downloadObjectToFile() async throws {
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

    @Test func downloadObjectWithProgress() async throws {
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

        var progressCalled = false
        _ = try await client.downloadObject(
            bucket: bucket,
            key: key,
            to: tempFile,
            progress: { _, _ in
                progressCalled = true
            }
        )

        #expect(progressCalled)
    }

    @Test func getObjectRange() async throws {
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
```

**Step 2: Run the object tests**

Run: `swift test --filter IntegrationTests.ObjectTests 2>&1 | tail -30`
Expected: All object tests pass

**Step 3: Commit**

```bash
git add Tests/IntegrationTests/ObjectTests.swift
git commit -m "feat: add object integration tests"
```

---

## Task 8: Create MultipartTests

**Files:**
- Create: `Tests/IntegrationTests/MultipartTests.swift`

**Step 1: Write the multipart integration tests**

```swift
import Testing
import Foundation
@testable import SwiftS3

@Suite("Multipart Upload Operations", .serialized)
struct MultipartTests {
    init() async throws {
        try await MinioTestServer.shared.ensureRunning()
    }

    @Test func fullMultipartUploadFlow() async throws {
        let client = TestConfig.createClient()
        let bucket = TestConfig.uniqueBucketName(prefix: "multi")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucket(client, bucket) } }

        let key = "multipart-test.bin"

        // Create multipart upload
        let upload = try await client.createMultipartUpload(bucket: bucket, key: key, contentType: "application/octet-stream")
        #expect(!upload.uploadId.isEmpty)
        #expect(upload.bucket == bucket)
        #expect(upload.key == key)

        // Upload two parts (minimum part size for S3 is 5MB, but minio is more lenient)
        let part1Data = randomData(size: 1024)
        let part2Data = randomData(size: 1024)

        let completedPart1 = try await client.uploadPart(
            bucket: bucket,
            key: key,
            uploadId: upload.uploadId,
            partNumber: 1,
            data: part1Data
        )
        #expect(completedPart1.partNumber == 1)
        #expect(!completedPart1.etag.isEmpty)

        let completedPart2 = try await client.uploadPart(
            bucket: bucket,
            key: key,
            uploadId: upload.uploadId,
            partNumber: 2,
            data: part2Data
        )
        #expect(completedPart2.partNumber == 2)

        // Complete the upload
        let etag = try await client.completeMultipartUpload(
            bucket: bucket,
            key: key,
            uploadId: upload.uploadId,
            parts: [completedPart1, completedPart2]
        )
        #expect(!etag.isEmpty)

        // Verify the complete object
        let (data, metadata) = try await client.getObject(bucket: bucket, key: key)
        #expect(data == part1Data + part2Data)
        #expect(metadata.contentLength == Int64(part1Data.count + part2Data.count))
    }

    @Test func abortMultipartUpload() async throws {
        let client = TestConfig.createClient()
        let bucket = TestConfig.uniqueBucketName(prefix: "abort")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucket(client, bucket) } }

        let key = "abort-test.bin"

        // Create multipart upload
        let upload = try await client.createMultipartUpload(bucket: bucket, key: key)

        // Upload one part
        _ = try await client.uploadPart(
            bucket: bucket,
            key: key,
            uploadId: upload.uploadId,
            partNumber: 1,
            data: randomData(size: 512)
        )

        // Abort the upload
        try await client.abortMultipartUpload(bucket: bucket, key: key, uploadId: upload.uploadId)

        // Verify no incomplete uploads remain
        let uploads = try await client.listMultipartUploads(bucket: bucket)
        #expect(!uploads.uploads.contains { $0.uploadId == upload.uploadId })
    }

    @Test func listParts() async throws {
        let client = TestConfig.createClient()
        let bucket = TestConfig.uniqueBucketName(prefix: "parts")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucket(client, bucket) } }

        let key = "list-parts-test.bin"

        // Create multipart upload
        let upload = try await client.createMultipartUpload(bucket: bucket, key: key)
        defer { Task { try? await client.abortMultipartUpload(bucket: bucket, key: key, uploadId: upload.uploadId) } }

        // Upload three parts
        for partNum in 1...3 {
            _ = try await client.uploadPart(
                bucket: bucket,
                key: key,
                uploadId: upload.uploadId,
                partNumber: partNum,
                data: randomData(size: 256)
            )
        }

        // List parts
        let partsResult = try await client.listParts(bucket: bucket, key: key, uploadId: upload.uploadId)
        #expect(partsResult.parts.count == 3)
        #expect(partsResult.parts.map(\.partNumber).sorted() == [1, 2, 3])
    }

    @Test func listMultipartUploads() async throws {
        let client = TestConfig.createClient()
        let bucket = TestConfig.uniqueBucketName(prefix: "listuploads")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucket(client, bucket) } }

        // Create multiple incomplete uploads
        let upload1 = try await client.createMultipartUpload(bucket: bucket, key: "upload1.bin")
        let upload2 = try await client.createMultipartUpload(bucket: bucket, key: "upload2.bin")
        defer {
            Task {
                try? await client.abortMultipartUpload(bucket: bucket, key: "upload1.bin", uploadId: upload1.uploadId)
                try? await client.abortMultipartUpload(bucket: bucket, key: "upload2.bin", uploadId: upload2.uploadId)
            }
        }

        // List multipart uploads
        let result = try await client.listMultipartUploads(bucket: bucket)
        #expect(result.uploads.count >= 2)
        #expect(result.uploads.contains { $0.key == "upload1.bin" })
        #expect(result.uploads.contains { $0.key == "upload2.bin" })
    }
}
```

**Step 2: Run the multipart tests**

Run: `swift test --filter IntegrationTests.MultipartTests 2>&1 | tail -20`
Expected: All multipart tests pass

**Step 3: Commit**

```bash
git add Tests/IntegrationTests/MultipartTests.swift
git commit -m "feat: add multipart upload integration tests"
```

---

## Task 9: Create CLIRunner helper for ss3 tests

**Files:**
- Create: `Tests/ss3IntegrationTests/CLIRunner.swift`

**Step 1: Write the CLIRunner helper**

```swift
import Foundation

/// Result of running an ss3 CLI command.
struct CLIResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }
}

/// Runs the ss3 CLI binary and captures output.
enum CLIRunner {
    /// Path to the built ss3 binary.
    static var binaryPath: String {
        // Swift test runs from package directory, binary is in .build/debug/
        let possiblePaths = [
            ".build/debug/ss3",
            "../.build/debug/ss3",
            "../../.build/debug/ss3"
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Fall back to building the path from current directory
        let cwd = FileManager.default.currentDirectoryPath
        return "\(cwd)/.build/debug/ss3"
    }

    /// Environment variables for connecting to minio test server.
    static var minioEnv: [String: String] {
        [
            "SS3_ENDPOINT": MinioTestServer.endpoint,
            "SS3_REGION": "us-east-1",
            "SS3_ACCESS_KEY": MinioTestServer.accessKey,
            "SS3_SECRET_KEY": MinioTestServer.secretKey
        ]
    }

    /// Runs ss3 with the given arguments.
    /// - Parameters:
    ///   - args: Command line arguments (e.g., "ls", "s3://bucket")
    ///   - env: Additional environment variables to merge with minio config
    /// - Returns: CLIResult with exit code and captured output
    static func run(_ args: String..., env: [String: String] = [:]) async throws -> CLIResult {
        try await run(arguments: args, env: env)
    }

    /// Runs ss3 with the given arguments array.
    static func run(arguments: [String], env: [String: String] = [:]) async throws -> CLIResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments

        // Merge base minio env with any custom env
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in minioEnv {
            environment[key] = value
        }
        for (key, value) in env {
            environment[key] = value
        }
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return CLIResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}
```

**Step 2: Verify file compiles**

Run: `swift build --target ss3IntegrationTests 2>&1 | head -20`
Expected: Builds without errors

**Step 3: Commit**

```bash
git add Tests/ss3IntegrationTests/CLIRunner.swift
git commit -m "feat: add CLIRunner helper for CLI integration tests"
```

---

## Task 10: Create ss3IntegrationTests test helpers

**Files:**
- Create: `Tests/ss3IntegrationTests/CLITestHelpers.swift`

**Step 1: Write the CLI test helpers**

```swift
import Foundation
import SwiftS3

/// Shared utilities for CLI integration tests.
/// Reuses MinioTestServer from IntegrationTests.
enum CLITestConfig {
    static var s3Configuration: S3Configuration {
        S3Configuration(
            accessKeyId: MinioTestServer.accessKey,
            secretAccessKey: MinioTestServer.secretKey,
            region: "us-east-1",
            endpoint: URL(string: MinioTestServer.endpoint)!,
            usePathStyle: true
        )
    }

    static func createClient() -> S3Client {
        S3Client(configuration: s3Configuration)
    }

    static func uniqueBucketName(prefix: String = "cli") -> String {
        let uuid = UUID().uuidString.prefix(8).lowercased()
        return "\(prefix)-\(uuid)"
    }
}

/// Cleans up a bucket via the library (not CLI) for reliability.
func cleanupBucketViaCLI(_ bucketName: String) async {
    let client = CLITestConfig.createClient()
    do {
        let result = try await client.listObjects(bucket: bucketName)
        for object in result.objects {
            try? await client.deleteObject(bucket: bucketName, key: object.key)
        }
        try await client.deleteBucket(bucketName)
    } catch {
        // Ignore cleanup errors
    }
}
```

**Step 2: Copy MinioTestServer to ss3IntegrationTests**

Since ss3IntegrationTests is a separate target, we need to either:
- Make MinioTestServer public and importable, or
- Copy it to the ss3IntegrationTests directory

For simplicity, we'll create a shared reference. Add to the file:

```swift
// Note: This file imports MinioTestServer from the same test bundle.
// The MinioTestServer.swift file needs to be accessible from both test targets.
```

Actually, since both test targets are separate, we need to duplicate or share the MinioTestServer. The cleanest approach is to put shared code in a test support module or duplicate minimally. Let's create a minimal copy for ss3IntegrationTests.

**Step 3: Verify file compiles**

We need MinioTestServer accessible. Let's add the same file to ss3IntegrationTests target.

Run: `cp Tests/IntegrationTests/MinioTestServer.swift Tests/ss3IntegrationTests/`

**Step 4: Commit**

```bash
git add Tests/ss3IntegrationTests/CLITestHelpers.swift Tests/ss3IntegrationTests/MinioTestServer.swift
git commit -m "feat: add CLI test helpers and MinioTestServer for ss3 integration tests"
```

---

## Task 11: Create ListTests for ss3 ls command

**Files:**
- Create: `Tests/ss3IntegrationTests/ListTests.swift`

**Step 1: Write the ls command integration tests**

```swift
import Testing
import Foundation
import SwiftS3

@Suite("ss3 ls Command", .serialized)
struct ListTests {
    init() async throws {
        try await MinioTestServer.shared.ensureRunning()
    }

    @Test func listBucketsHumanFormat() async throws {
        let client = CLITestConfig.createClient()
        let bucket = CLITestConfig.uniqueBucketName(prefix: "lsbucket")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucketViaCLI(bucket) } }

        let result = try await CLIRunner.run("ls")

        #expect(result.succeeded)
        #expect(result.stdout.contains(bucket))
        #expect(result.stdout.contains("BUCKET")) // Human format has header
    }

    @Test func listBucketsJSONFormat() async throws {
        let client = CLITestConfig.createClient()
        let bucket = CLITestConfig.uniqueBucketName(prefix: "lsjson")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucketViaCLI(bucket) } }

        let result = try await CLIRunner.run("ls", "--format", "json")

        #expect(result.succeeded)
        #expect(result.stdout.contains(bucket))
        #expect(result.stdout.hasPrefix("[")) // JSON array
    }

    @Test func listBucketsTSVFormat() async throws {
        let client = CLITestConfig.createClient()
        let bucket = CLITestConfig.uniqueBucketName(prefix: "lstsv")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucketViaCLI(bucket) } }

        let result = try await CLIRunner.run("ls", "--format", "tsv")

        #expect(result.succeeded)
        #expect(result.stdout.contains(bucket))
        #expect(result.stdout.contains("\t")) // TSV has tabs
    }

    @Test func listObjectsInBucket() async throws {
        let client = CLITestConfig.createClient()
        let bucket = CLITestConfig.uniqueBucketName(prefix: "lsobj")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucketViaCLI(bucket) } }

        // Upload test objects
        _ = try await client.putObject(bucket: bucket, key: "file1.txt", data: Data("content1".utf8))
        _ = try await client.putObject(bucket: bucket, key: "file2.txt", data: Data("content2".utf8))

        let result = try await CLIRunner.run("ls", "s3://\(bucket)/")

        #expect(result.succeeded)
        #expect(result.stdout.contains("file1.txt"))
        #expect(result.stdout.contains("file2.txt"))
    }

    @Test func listObjectsWithPrefix() async throws {
        let client = CLITestConfig.createClient()
        let bucket = CLITestConfig.uniqueBucketName(prefix: "lsprefix")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucketViaCLI(bucket) } }

        // Upload objects with different prefixes
        _ = try await client.putObject(bucket: bucket, key: "docs/readme.txt", data: Data("readme".utf8))
        _ = try await client.putObject(bucket: bucket, key: "docs/guide.txt", data: Data("guide".utf8))
        _ = try await client.putObject(bucket: bucket, key: "images/logo.png", data: Data("logo".utf8))

        let result = try await CLIRunner.run("ls", "s3://\(bucket)/docs/")

        #expect(result.succeeded)
        #expect(result.stdout.contains("readme.txt"))
        #expect(result.stdout.contains("guide.txt"))
        #expect(!result.stdout.contains("logo.png"))
    }

    @Test func listObjectsShowsFolders() async throws {
        let client = CLITestConfig.createClient()
        let bucket = CLITestConfig.uniqueBucketName(prefix: "lsfolder")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucketViaCLI(bucket) } }

        // Upload objects in folder structure
        _ = try await client.putObject(bucket: bucket, key: "folder1/file.txt", data: Data("f1".utf8))
        _ = try await client.putObject(bucket: bucket, key: "folder2/file.txt", data: Data("f2".utf8))

        let result = try await CLIRunner.run("ls", "s3://\(bucket)/")

        #expect(result.succeeded)
        #expect(result.stdout.contains("folder1/"))
        #expect(result.stdout.contains("folder2/"))
    }

    @Test func listObjectsJSONFormat() async throws {
        let client = CLITestConfig.createClient()
        let bucket = CLITestConfig.uniqueBucketName(prefix: "lsobjjson")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucketViaCLI(bucket) } }

        _ = try await client.putObject(bucket: bucket, key: "test.txt", data: Data("test".utf8))

        let result = try await CLIRunner.run("ls", "s3://\(bucket)/", "--format", "json")

        #expect(result.succeeded)
        #expect(result.stdout.contains("test.txt"))
        #expect(result.stdout.contains("\"key\"")) // JSON field
    }

    @Test func listNonexistentBucketFails() async throws {
        let result = try await CLIRunner.run("ls", "s3://nonexistent-bucket-xyz123/")

        #expect(!result.succeeded)
        #expect(result.exitCode == 1)
    }
}
```

**Step 2: Run the list tests**

Run: `swift test --filter ss3IntegrationTests.ListTests 2>&1 | tail -30`
Expected: All list tests pass

**Step 3: Commit**

```bash
git add Tests/ss3IntegrationTests/ListTests.swift
git commit -m "feat: add ss3 ls command integration tests"
```

---

## Task 12: Create CopyTests for ss3 cp command

**Files:**
- Create: `Tests/ss3IntegrationTests/CopyTests.swift`

**Step 1: Write the cp command integration tests**

```swift
import Testing
import Foundation
import SwiftS3

@Suite("ss3 cp Command", .serialized)
struct CopyTests {
    init() async throws {
        try await MinioTestServer.shared.ensureRunning()
    }

    @Test func uploadSmallFile() async throws {
        let client = CLITestConfig.createClient()
        let bucket = CLITestConfig.uniqueBucketName(prefix: "cpup")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucketViaCLI(bucket) } }

        // Create temp file
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-test-\(UUID().uuidString).txt")
        let content = "Hello from CLI upload test!"
        try content.write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        // Upload via CLI
        let result = try await CLIRunner.run("cp", tempFile.path, "s3://\(bucket)/uploaded.txt")

        #expect(result.succeeded)
        #expect(result.stdout.contains("Uploaded"))

        // Verify via library
        let (data, _) = try await client.getObject(bucket: bucket, key: "uploaded.txt")
        #expect(String(data: data, encoding: .utf8) == content)
    }

    @Test func uploadToKeyWithTrailingSlash() async throws {
        let client = CLITestConfig.createClient()
        let bucket = CLITestConfig.uniqueBucketName(prefix: "cpslash")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucketViaCLI(bucket) } }

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("myfile.txt")
        try "content".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        // Upload to "folder/" - should use filename as key
        let result = try await CLIRunner.run("cp", tempFile.path, "s3://\(bucket)/folder/")

        #expect(result.succeeded)

        // Verify file was uploaded with original name
        let objects = try await client.listObjects(bucket: bucket, prefix: "folder/")
        #expect(objects.objects.contains { $0.key == "folder/myfile.txt" })
    }

    @Test func downloadFile() async throws {
        let client = CLITestConfig.createClient()
        let bucket = CLITestConfig.uniqueBucketName(prefix: "cpdown")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucketViaCLI(bucket) } }

        // Upload via library
        let content = "Content to download via CLI"
        _ = try await client.putObject(bucket: bucket, key: "download-me.txt", data: Data(content.utf8))

        // Download via CLI
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("downloaded-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let result = try await CLIRunner.run("cp", "s3://\(bucket)/download-me.txt", tempFile.path)

        #expect(result.succeeded)
        #expect(result.stdout.contains("Downloaded"))

        // Verify downloaded content
        let downloaded = try String(contentsOf: tempFile, encoding: .utf8)
        #expect(downloaded == content)
    }

    @Test func downloadToDirectory() async throws {
        let client = CLITestConfig.createClient()
        let bucket = CLITestConfig.uniqueBucketName(prefix: "cpdir")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucketViaCLI(bucket) } }

        _ = try await client.putObject(bucket: bucket, key: "folder/myfile.txt", data: Data("content".utf8))

        // Create temp directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("download-dir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Download to directory (should keep original filename)
        let result = try await CLIRunner.run("cp", "s3://\(bucket)/folder/myfile.txt", tempDir.path)

        #expect(result.succeeded)

        // Verify file exists with original name
        let downloadedFile = tempDir.appendingPathComponent("myfile.txt")
        #expect(FileManager.default.fileExists(atPath: downloadedFile.path))
    }

    @Test func uploadNonexistentFileFails() async throws {
        let client = CLITestConfig.createClient()
        let bucket = CLITestConfig.uniqueBucketName(prefix: "cpfail")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucketViaCLI(bucket) } }

        let result = try await CLIRunner.run("cp", "/nonexistent/file.txt", "s3://\(bucket)/key")

        #expect(!result.succeeded)
        #expect(result.exitCode == 1)
    }

    @Test func downloadNonexistentKeyFails() async throws {
        let client = CLITestConfig.createClient()
        let bucket = CLITestConfig.uniqueBucketName(prefix: "cpnokey")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucketViaCLI(bucket) } }

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("should-not-exist-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let result = try await CLIRunner.run("cp", "s3://\(bucket)/nonexistent-key.txt", tempFile.path)

        #expect(!result.succeeded)
        #expect(result.exitCode == 1)
        #expect(!FileManager.default.fileExists(atPath: tempFile.path))
    }

    @Test func copyBothLocalPathsFails() async throws {
        let tempFile1 = FileManager.default.temporaryDirectory.appendingPathComponent("file1.txt")
        let tempFile2 = FileManager.default.temporaryDirectory.appendingPathComponent("file2.txt")
        try "content".write(to: tempFile1, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile1) }

        let result = try await CLIRunner.run("cp", tempFile1.path, tempFile2.path)

        #expect(!result.succeeded)
        #expect(result.stderr.contains("one local and one remote"))
    }

    @Test func uploadLargeFileUsesMultipart() async throws {
        let client = CLITestConfig.createClient()
        let bucket = CLITestConfig.uniqueBucketName(prefix: "cpmulti")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucketViaCLI(bucket) } }

        // Create file larger than default multipart threshold (use smaller for test)
        // We'll use --multipart-threshold to force multipart
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("large-\(UUID().uuidString).bin")

        // Create 1MB file
        let data = Data(repeating: 0x42, count: 1_000_000)
        try data.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        // Upload with low threshold to trigger multipart
        let result = try await CLIRunner.run(
            "cp",
            tempFile.path,
            "s3://\(bucket)/large.bin",
            "--multipart-threshold", "100000",  // 100KB
            "--chunk-size", "100000"
        )

        #expect(result.succeeded)

        // Verify upload
        let metadata = try await client.headObject(bucket: bucket, key: "large.bin")
        #expect(metadata.contentLength == Int64(data.count))
    }
}
```

**Step 2: Run the copy tests**

Run: `swift test --filter ss3IntegrationTests.CopyTests 2>&1 | tail -30`
Expected: All copy tests pass

**Step 3: Commit**

```bash
git add Tests/ss3IntegrationTests/CopyTests.swift
git commit -m "feat: add ss3 cp command integration tests"
```

---

## Task 13: Update GitHub Actions CI workflow

**Files:**
- Modify: `.github/workflows/ci.yml`

**Step 1: Replace ci.yml with updated version**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  lint:
    name: SwiftLint
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - name: Install SwiftLint
        run: brew install swiftlint
      - name: Run SwiftLint
        run: swiftlint --strict

  unit-tests-macos:
    name: Unit Tests (macOS)
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - name: Build
        run: swift build
      - name: Run SwiftS3 Tests
        run: swift test --filter SwiftS3Tests
      - name: Run ss3 Tests
        run: swift test --filter ss3Tests

  unit-tests-linux:
    name: Unit Tests (Linux)
    runs-on: ubuntu-24.04
    container:
      image: swift:6.2-noble
    steps:
      - uses: actions/checkout@v4
      - name: Build
        run: swift build
      - name: Run SwiftS3 Tests
        run: swift test --filter SwiftS3Tests
      - name: Run ss3 Tests
        run: swift test --filter ss3Tests

  integration-tests-macos:
    name: Integration Tests (macOS)
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - name: Setup minio
        run: ./Scripts/setup-minio.sh
      - name: Build
        run: swift build
      - name: Run Library Integration Tests
        run: swift test --filter IntegrationTests
      - name: Run CLI Integration Tests
        run: swift test --filter ss3IntegrationTests

  integration-tests-linux:
    name: Integration Tests (Linux)
    runs-on: ubuntu-24.04
    container:
      image: swift:6.2-noble
    steps:
      - uses: actions/checkout@v4
      - name: Install curl
        run: apt-get update && apt-get install -y curl
      - name: Setup minio
        run: ./Scripts/setup-minio.sh
      - name: Build
        run: swift build
      - name: Run Library Integration Tests
        run: swift test --filter IntegrationTests
      - name: Run CLI Integration Tests
        run: swift test --filter ss3IntegrationTests
```

**Step 2: Verify YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"`
Expected: No errors

**Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "feat: add integration test jobs to CI workflow"
```

---

## Task 14: Update CLAUDE.md with integration test instructions

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Add testing section after Build Commands**

Add after the "## Build Commands" section:

```markdown
## Testing

### Unit Tests (fast, no dependencies)

```bash
# Run all unit tests
swift test --filter SwiftS3Tests
swift test --filter ss3Tests

# Run specific unit test
swift test --filter SwiftS3Tests.SigV4SignerTests/testCanonicalRequest
```

### Integration Tests (requires minio)

Integration tests use minio as an S3-compatible server. First-time setup:

```bash
# Download minio binary (one-time setup)
./Scripts/setup-minio.sh
```

Then run integration tests (minio starts automatically):

```bash
# Library integration tests
swift test --filter IntegrationTests

# CLI integration tests
swift test --filter ss3IntegrationTests
```

### Pre-commit Checklist

**IMPORTANT:** Run all of these before every commit:

1. `swiftlint` - Fix all violations
2. `swift test --filter SwiftS3Tests && swift test --filter ss3Tests` - Unit tests
3. `swift test --filter IntegrationTests && swift test --filter ss3IntegrationTests` - Integration tests
```

**Step 2: Update the existing Build Commands section**

The existing section shows `swift test` - leave it for running all tests, but the new section provides more granular options.

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add integration test instructions to CLAUDE.md"
```

---

## Task 15: Run full test suite and verify

**Files:**
- None (verification only)

**Step 1: Run swiftlint**

Run: `swiftlint`
Expected: No violations

**Step 2: Run all unit tests**

Run: `swift test --filter SwiftS3Tests && swift test --filter ss3Tests`
Expected: All pass

**Step 3: Run all integration tests**

Run: `swift test --filter IntegrationTests && swift test --filter ss3IntegrationTests`
Expected: All pass

**Step 4: Final verification**

Run: `swift test`
Expected: All 4 test targets pass

**Step 5: Create summary commit if any fixups needed**

If any fixes were needed during verification, commit them:

```bash
git add -A
git commit -m "fix: address issues found during final verification"
```

---

## Summary

This plan creates:
- 1 setup script (`Scripts/setup-minio.sh`)
- 1 gitignore update (`.minio/`)
- 2 test targets in `Package.swift`
- 3 library integration test files (MinioTestServer, TestHelpers, BucketTests, ObjectTests, MultipartTests)
- 4 CLI integration test files (CLIRunner, CLITestHelpers, MinioTestServer, ListTests, CopyTests)
- 1 CI workflow update
- 1 CLAUDE.md documentation update

Total: ~15 commits of incremental, tested changes.
