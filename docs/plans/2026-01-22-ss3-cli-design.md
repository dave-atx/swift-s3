# ss3 CLI Tool Design

**Issue:** https://github.com/dave-atx/swift-s3/issues/11
**Date:** 2026-01-22

## Overview

A command-line tool `ss3` that wraps the SwiftS3 library to interact with S3-compatible APIs (AWS S3, Backblaze B2, Cloudflare R2, GCS).

## Requirements

- No external dependencies except swift.org/Apple packages
- macOS 26+ and Linux (Swift Static Linux SDK)
- Swift 6.2 with strict concurrency
- Parallelized operations where applicable

## Project Structure

```
Sources/
├── SwiftS3/          # Existing library (unchanged)
└── ss3/              # New CLI executable
    ├── main.swift              # Entry point, registers commands
    ├── Commands/
    │   ├── ListCommand.swift   # ss3 ls
    │   └── CopyCommand.swift   # ss3 cp
    ├── Configuration/
    │   ├── GlobalOptions.swift # Shared flags (credentials, endpoint, etc.)
    │   └── Environment.swift   # SS3_* env var resolution
    ├── Output/
    │   ├── Formatter.swift     # Protocol for output formatting
    │   ├── HumanFormatter.swift
    │   ├── JSONFormatter.swift
    │   └── TSVFormatter.swift
    └── Transfer/
        └── MultipartUploader.swift  # Parallel chunked uploads
```

### Package.swift Changes

```swift
dependencies: [
    .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
],
targets: [
    // ... existing targets ...
    .executableTarget(
        name: "ss3",
        dependencies: [
            "SwiftS3",
            .product(name: "ArgumentParser", package: "swift-argument-parser")
        ],
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency")
        ]
    ),
    .testTarget(
        name: "ss3Tests",
        dependencies: ["ss3"]
    )
]
```

## Command Line Interface

### Global Options

```swift
struct GlobalOptions: ParsableArguments {
    @Option(name: [.long, .customShort("u")], help: "Access key ID")
    var keyId: String?

    @Option(name: [.long, .customShort("p")], help: "Secret access key")
    var secretKey: String?

    @Option(help: "AWS region")
    var region: String?

    @Option(help: "S3 endpoint URL")
    var endpoint: String?

    @Option(help: "Bucket name")
    var bucket: String?

    @Flag(help: "Use Backblaze B2 (sets endpoint to https://s3.<region>.backblazeb2.com)")
    var b2: Bool = false

    @Flag(help: "Verbose error output")
    var verbose: Bool = false

    @Option(help: "Output format")
    var format: OutputFormat = .human
}
```

### Configuration Resolution

**Priority order:** Command-line flag → Environment variable → Error

**Environment variables:**
- `SS3_KEY_ID` - Access key ID
- `SS3_SECRET_KEY` - Secret access key
- `SS3_REGION` - AWS region
- `SS3_ENDPOINT` - S3 endpoint URL
- `SS3_BUCKET` - Default bucket

**Future consideration:** Structure code to allow easy integration of [swift-configuration](https://swiftpackageindex.com/apple/swift-configuration) for config file support.

### Commands

#### List Command

```
ss3 ls [options] [[bucket][/path]]
```

- No argument: List all buckets
- Bucket only: List objects in bucket root
- Bucket/path: List objects with prefix

#### Copy Command

```
ss3 cp [options] <source> <destination>
```

**Path notation:**
- Local: `/path/to/file`, `./relative/path`, `file.txt`
- Remote: `bucket/key` or `bucket/` (directory target)

**Constraints:**
- Exactly one local and one remote path required
- Single files only (no recursive directory support)
- If remote destination is bucket or directory, uses local filename

**Transfer options:**
```swift
@Option(help: "Multipart threshold in bytes (default: 100MB)")
var multipartThreshold: Int64 = 100 * 1024 * 1024

@Option(help: "Chunk size in bytes (default: 10MB)")
var chunkSize: Int64 = 10 * 1024 * 1024

@Option(help: "Max parallel chunk uploads (default: 4)")
var parallel: Int = 4
```

## Parallel Multipart Uploads

### Configuration Defaults

| Setting | Default | Flag |
|---------|---------|------|
| Threshold | 100 MB | `--multipart-threshold` |
| Chunk size | 10 MB | `--chunk-size` |
| Parallelism | 4 | `--parallel` |

### Upload Flow

```
1. Check file size
2. If size < threshold:
   → Single putObject() call
3. If size >= threshold:
   a. createMultipartUpload()
   b. Split file into chunks
   c. Upload chunks in parallel via TaskGroup (limited by --parallel)
   d. Collect CompletedPart results
   e. completeMultipartUpload()
   f. On failure → abortMultipartUpload() and report error
```

### Implementation

```swift
func uploadLargeFile(
    client: S3Client,
    bucket: String,
    key: String,
    fileURL: URL,
    chunkSize: Int64,
    maxParallel: Int
) async throws {
    let upload = try await client.createMultipartUpload(bucket: bucket, key: key)

    do {
        let chunks = calculateChunks(fileURL: fileURL, chunkSize: chunkSize)

        let parts = try await withThrowingTaskGroup(of: CompletedPart.self) { group in
            var pending = chunks.makeIterator()
            var inFlight = 0
            var results: [CompletedPart] = []

            // Seed initial batch up to parallelism limit
            while inFlight < maxParallel, let chunk = pending.next() {
                group.addTask {
                    try await self.uploadChunk(client: client, bucket: bucket,
                                               key: key, uploadId: upload.uploadId, chunk: chunk)
                }
                inFlight += 1
            }

            // As each completes, start next chunk
            for try await part in group {
                results.append(part)
                if let chunk = pending.next() {
                    group.addTask {
                        try await self.uploadChunk(client: client, bucket: bucket,
                                                   key: key, uploadId: upload.uploadId, chunk: chunk)
                    }
                }
            }
            return results
        }

        try await client.completeMultipartUpload(
            bucket: bucket, key: key, uploadId: upload.uploadId, parts: parts
        )
    } catch {
        try? await client.abortMultipartUpload(
            bucket: bucket, key: key, uploadId: upload.uploadId
        )
        throw error
    }
}
```

## Output Formatting

### Formatter Protocol

```swift
protocol OutputFormatter {
    func formatBuckets(_ buckets: [Bucket]) -> String
    func formatObjects(_ objects: [S3Object], prefixes: [String]) -> String
    func formatProgress(transferred: Int64, total: Int64) -> String
    func formatSuccess(message: String) -> String
    func formatError(_ error: Error, verbose: Bool) -> String
}
```

### Human Format (default)

```
$ ss3 ls mybucket/
       1.2 KB  2024-01-15 10:30  config.json
      45.6 MB  2024-01-14 09:15  backup.tar.gz
               2024-01-13 08:00  logs/
3 items (45.6 MB total)
```

### JSON Format

```json
[
  {"key": "config.json", "size": 1229, "lastModified": "2024-01-15T10:30:00Z"},
  {"key": "backup.tar.gz", "size": 47829504, "lastModified": "2024-01-14T09:15:00Z"},
  {"key": "logs/", "size": 0, "lastModified": "2024-01-13T08:00:00Z"}
]
```

### TSV Format

Tab-separated, no headers, suitable for scripting with `cut`/`awk`:

```
config.json	1229	2024-01-15T10:30:00Z
backup.tar.gz	47829504	2024-01-14T09:15:00Z
logs/	0	2024-01-13T08:00:00Z
```

## Error Handling

### User-Friendly Output (default)

```
Error: Access denied
Hint: Check that your credentials have permission for this bucket
```

### Verbose Output (--verbose)

```
Error: Access denied
Code: AccessDenied
Resource: /mybucket/secret.txt
RequestId: ABC123XYZ
Hint: Check that your credentials have permission for this bucket
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | User/client error (bad arguments, access denied, not found) |
| 2 | Server/network error (timeout, 5xx responses) |

## Testing Strategy

### Unit Tests (`Tests/ss3Tests/`)

1. **Argument parsing** - Flag/env resolution, priority order, validation
2. **Formatter tests** - Each output format produces expected strings
3. **Chunk calculation** - File splitting for various sizes and configs
4. **Path parsing** - Local vs remote detection, bucket/key extraction

### Integration Tests (mocked S3Client)

1. **List command** - Buckets, objects, pagination handling
2. **Copy command** - Small file upload, download, multipart flow
3. **Error scenarios** - Missing credentials, access denied, network failure

### Testing Approach

- Extract `S3Client` creation into factory/protocol for test injection
- Reuse existing `HTTPClientProtocol` mock pattern from library tests
- Formatter tests are pure functions, no mocking needed
- No live tests in CLI (library already has live tests)

## Implementation Phases

### Phase 1: Foundation
- Package.swift updates
- GlobalOptions and Environment resolution
- Basic `ss3 --help` working

### Phase 2: List Command
- `ss3 ls` (buckets)
- `ss3 ls bucket/path` (objects)
- All three output formats

### Phase 3: Copy Command (Simple)
- Upload small files (single PUT)
- Download files
- Path parsing and validation

### Phase 4: Parallel Multipart
- Chunk calculation
- TaskGroup-based parallel uploads
- Progress reporting

### Phase 5: Polish
- Error messages and hints
- Edge cases and validation
- Documentation
