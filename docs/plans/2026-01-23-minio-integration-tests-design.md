# Minio Integration Tests Design

**Issue:** https://github.com/dave-atx/swift-s3/issues/13
**Date:** 2026-01-23

## Overview

Add integration tests using minio as an S3-compatible server. Tests cover both the SwiftS3 library and the ss3 CLI tool.

## Requirements

- Local testing without Docker
- Works on macOS and Linux
- Tests clean up after themselves
- GitHub Actions runs tests on both platforms
- Comprehensive coverage of library and CLI

## Minio Installation

Use standalone minio binary downloaded to `.minio/minio` (gitignored). A setup script (`Scripts/setup-minio.sh`) detects the platform and downloads the correct binary from minio's official releases.

Supported platforms:
- macOS arm64
- macOS x86_64
- Linux x86_64

## Test Organization

### Directory Structure

```
Scripts/
  setup-minio.sh              # Downloads minio binary if not present

Tests/
  SwiftS3Tests/               # Existing unit tests (unchanged)
  ss3Tests/                   # Existing unit tests (unchanged)
  IntegrationTests/           # New: library integration tests
    MinioTestServer.swift     # Starts/stops minio process
    TestHelpers.swift         # Bucket creation, cleanup utilities
    BucketTests.swift         # Bucket operation tests
    ObjectTests.swift         # Object operation tests
    MultipartTests.swift      # Multipart upload tests
  ss3IntegrationTests/        # New: CLI integration tests
    CLIRunner.swift           # Runs ss3 binary, captures output
    ListTests.swift           # ls command tests
    CopyTests.swift           # cp command tests
```

### Package.swift Changes

Add two new test targets:
- `IntegrationTests` - depends on `SwiftS3`
- `ss3IntegrationTests` - depends on `ss3`

## Minio Server Lifecycle

### Configuration

- Port: `9199` (avoids conflicts with default minio port)
- Credentials: `minioadmin` / `minioadmin`
- Data directory: temp directory, deleted on shutdown
- Addressing: path-style (minio default)

### MinioTestServer

```swift
actor MinioTestServer {
    private var process: Process?
    private var dataDirectory: URL?

    static let port = 9199
    static let accessKey = "minioadmin"
    static let secretKey = "minioadmin"

    func ensureRunning() async throws
    func stop() async
    func waitForReady() async throws
}
```

- Starts minio once per test suite
- `waitForReady()` polls health endpoint until server responds
- `stop()` kills process and deletes data directory

### Test Configuration

```swift
static let testConfig = S3Configuration(
    accessKeyId: "minioadmin",
    secretAccessKey: "minioadmin",
    region: "us-east-1",
    endpoint: URL(string: "http://127.0.0.1:9199")!
)
```

## Test Isolation

Each test creates its own bucket with a UUID suffix:

```swift
@Test func uploadAndDownloadObject() async throws {
    let bucket = "test-\(UUID().uuidString.prefix(8).lowercased())"
    let client = S3Client(configuration: Self.testConfig)

    try await client.createBucket(bucket: bucket)
    defer { Task { try? await cleanupBucket(client, bucket) } }

    // ... test logic ...
}
```

Cleanup strategy:
1. Each test cleans up its own bucket in a `defer` block
2. Server shutdown deletes entire data directory as safety net
3. Use `try?` for cleanup to avoid masking test failures

## Test Coverage

### Library Tests (IntegrationTests)

**Bucket operations:**
- `listBuckets` - list all buckets
- `createBucket` - create new bucket
- `deleteBucket` - delete empty bucket
- `headBucket` - check bucket exists

**Object operations:**
- `listObjects` / `listObjectsV2` - list with pagination, prefixes, delimiters
- `putObject` - upload small objects
- `getObject` - download to memory
- `downloadObject` - download to file with progress
- `headObject` - get metadata
- `deleteObject` - delete single object
- `deleteObjects` - batch delete
- `copyObject` - copy between keys/buckets

**Multipart operations:**
- `createMultipartUpload` / `uploadPart` / `completeMultipartUpload` - full flow
- `abortMultipartUpload` - cleanup incomplete uploads
- `listParts` - verify uploaded parts

### CLI Tests (ss3IntegrationTests)

**Commands:**
- `ss3 ls` - list buckets
- `ss3 ls s3://bucket/prefix` - list objects
- `ss3 cp local s3://bucket/key` - upload (small and multipart)
- `ss3 cp s3://bucket/key local` - download

**Output formats:**
- Human-readable table format
- JSON format (parsed and validated)
- TSV format

## CLI Test Infrastructure

### CLIRunner

```swift
struct CLIRunner {
    static func run(_ args: String..., env: [String: String] = [:]) async throws -> CLIResult
}

struct CLIResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}
```

Finds the built `ss3` binary in `.build/debug/ss3` and executes it with the given arguments and environment.

### Environment Configuration

```swift
let env = [
    "SS3_ENDPOINT": "http://127.0.0.1:9199",
    "SS3_REGION": "us-east-1",
    "SS3_ACCESS_KEY": "minioadmin",
    "SS3_SECRET_KEY": "minioadmin"
]
```

## GitHub Actions CI

### Updated Job Structure

```yaml
jobs:
  lint:
    # unchanged

  unit-tests-macos:
    name: Unit Tests (macOS)
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - run: swift build
      - run: swift test --filter SwiftS3Tests
      - run: swift test --filter ss3Tests

  unit-tests-linux:
    name: Unit Tests (Linux)
    runs-on: ubuntu-24.04
    container:
      image: swift:6.2-noble
    steps:
      - uses: actions/checkout@v4
      - run: swift build
      - run: swift test --filter SwiftS3Tests
      - run: swift test --filter ss3Tests

  integration-tests-macos:
    name: Integration Tests (macOS)
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - run: ./Scripts/setup-minio.sh
      - run: swift build
      - run: swift test --filter IntegrationTests
      - run: swift test --filter ss3IntegrationTests

  integration-tests-linux:
    name: Integration Tests (Linux)
    runs-on: ubuntu-24.04
    container:
      image: swift:6.2-noble
    steps:
      - uses: actions/checkout@v4
      - run: ./Scripts/setup-minio.sh
      - run: swift build
      - run: swift test --filter IntegrationTests
      - run: swift test --filter ss3IntegrationTests
```

## CLAUDE.md Updates

Add testing instructions:

```markdown
## Testing

### Unit Tests (fast, no dependencies)
swift test --filter SwiftS3Tests
swift test --filter ss3Tests

### Integration Tests (requires minio)
# First time: download minio binary
./Scripts/setup-minio.sh

# Run integration tests (starts minio automatically)
swift test --filter IntegrationTests
swift test --filter ss3IntegrationTests

### Pre-commit Checklist
1. Run `swiftlint` and fix violations
2. Run unit tests
3. Run integration tests
```

## Implementation Files

| File | Purpose |
|------|---------|
| `Scripts/setup-minio.sh` | Download minio binary |
| `.gitignore` | Add `.minio/` |
| `Package.swift` | Add two test targets |
| `Tests/IntegrationTests/MinioTestServer.swift` | Server lifecycle |
| `Tests/IntegrationTests/TestHelpers.swift` | Shared utilities |
| `Tests/IntegrationTests/BucketTests.swift` | Bucket operations |
| `Tests/IntegrationTests/ObjectTests.swift` | Object operations |
| `Tests/IntegrationTests/MultipartTests.swift` | Multipart uploads |
| `Tests/ss3IntegrationTests/CLIRunner.swift` | CLI execution helper |
| `Tests/ss3IntegrationTests/ListTests.swift` | ls command tests |
| `Tests/ss3IntegrationTests/CopyTests.swift` | cp command tests |
| `.github/workflows/ci.yml` | Updated CI jobs |
| `CLAUDE.md` | Updated instructions |
