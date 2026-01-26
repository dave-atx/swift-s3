# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Lint the code (MUST run before builds and commits)
swiftlint

# Auto-fix lint violations
swiftlint --fix

# Build the project
swift build

# Run all tests
swift test

# Run a single test file
swift test --filter SwiftS3Tests.SigV4SignerTests

# Run a specific test
swift test --filter SwiftS3Tests.SigV4SignerTests/testCanonicalRequest

# Build for Linux (using Swift Static Linux SDK)
swift build --swift-sdk x86_64-swift-linux-musl
```

## Linting Requirements

**CRITICAL:** All code must pass linting locally before committing. Linting runs on both macOS and Linux in CI.

**Before every commit, verify linting passes on BOTH platforms:**

```bash
# On macOS
swiftlint --strict

# On Linux (using Docker or WSL)
docker run --rm -v $(pwd):/src swift:6.2-noble bash -c "cd /src && swiftlint --strict"
```

- Run `swiftlint --fix` locally to auto-fix simple violations
- Manually fix any remaining violations before proceeding
- Do not commit code with linting violations - CI will reject it
- All code must pass `swiftlint --strict` without violations

## Project Constraints

- Swift 6.2.x with strict concurrency enabled
- Cross-platform: macOS 26+ and Linux (Swift Static Linux SDK)
- No external dependencies - pure Swift implementation
- All public types must be `Sendable`
- Do not use `unsafe`, `@unchecked`, or `nonisolated(unsafe)` - prefer safe alternatives

## Architecture

This repository contains two main components:

### SwiftS3 Library (`Sources/SwiftS3/`)

Pure Swift S3-compatible API client supporting AWS S3, Backblaze B2, Cloudflare R2, and Google Cloud Storage.

**S3Client** (`Sources/SwiftS3/S3Client.swift`): Main public API providing 16 S3 operations (bucket CRUD, object CRUD, multipart uploads). All operations are `async throws`.

**SigV4Signer** (`Sources/SwiftS3/Auth/SigV4Signer.swift`): AWS Signature Version 4 implementation using pure Swift SHA256/HMAC-SHA256 (in `Extensions/Crypto.swift`).

**XMLResponseParser** (`Sources/SwiftS3/Internal/XMLResponseParser.swift`): Uses Foundation's `XMLParser` with separate delegate classes per response type to avoid shared state issues.

**RequestBuilder** (`Sources/SwiftS3/Internal/RequestBuilder.swift`): Constructs URLs and headers, supporting both virtual-hosted (AWS) and path-style (Backblaze/Cloudflare/GCS) addressing.

### ss3 CLI Tool (`Sources/ss3/`)

Command-line interface for S3 operations using the SwiftS3 library.

**GlobalOptions** (`Sources/ss3/Configuration/GlobalOptions.swift`): Handles global flags and environment variables for S3 configuration (endpoint, region, credentials, output format). Supports flag/environment resolution with B2 provider auto-configuration.

**Commands:**
- `ls`: List buckets and objects with configurable output formats
- `cp`: Upload/download objects with parallel multipart upload support

**Output Formats** (`Sources/ss3/Formatters/`):
- `HumanFormatter`: Human-readable table output (default)
- `JSONFormatter`: Machine-readable JSON output
- `TSVFormatter`: Tab-separated values for scripting

**Supporting Components:**
- `S3Path` (`Sources/ss3/Utilities/S3Path.swift`): Parses local and remote paths (e.g., `s3://bucket/key`, `/local/path`)
- `Environment` (`Sources/ss3/Configuration/Environment.swift`): Resolves `SS3_*` environment variables
- `MultipartUploader` (`Sources/ss3/Services/MultipartUploader.swift`): Handles parallel multipart uploads for large files
- `OutputFormat` & `OutputFormatter` (`Sources/ss3/Formatters/`): Pluggable output formatting for human/JSON/TSV

### Request Flow

1. `S3Client` calls `RequestBuilder` to construct the `URLRequest`
2. `SigV4Signer` signs the request (modifies headers in-place)
3. `HTTPClient` executes via `URLSession`
4. Response parsed by `XMLResponseParser` or error extracted from body

### Error Hierarchy

```
S3Error (protocol)
├── S3APIError    - Typed codes (AccessDenied, NoSuchBucket, etc.)
├── S3NetworkError - Wraps URLSession errors
└── S3ParsingError - XML parsing failures
```

### Platform Differences

- Streaming downloads (`getObjectStream`) are macOS-only due to `FoundationNetworking` limitations on Linux
- Uses conditional `#if !canImport(FoundationNetworking)` for platform-specific code

## ss3 CLI Usage

### Profile Option

```bash
ss3 --profile <name> <url> COMMAND [OPTIONS]
```

**Profile URL format:**
- Credentials in URL: `https://accessKey:secretKey@s3.example.com`
- Virtual-host bucket/region: `https://mybucket.s3.us-west-2.example.com`
- Simple endpoint: `https://s3.example.com` (region defaults to "auto")

**Environment variables for credentials:**
- `SS3_<NAME>_ACCESS_KEY`: Access key for profile `<NAME>`
- `SS3_<NAME>_SECRET_KEY`: Secret key for profile `<NAME>`
- Profile name is uppercased, non-alphanumeric chars become underscores

**Output formats:** human (default), json, tsv

### Path Format

Paths use `profile:bucket/key` format:
- `e2:` or `e2:/` - list buckets
- `e2:mybucket` - list bucket root
- `e2:mybucket/prefix` - list with prefix
- `e2:mybucket/path/file.txt` - specific object

Local paths have no colon: `./file.txt`, `/path/to/file`, `file.txt`

### Commands

**List buckets:**
```bash
ss3 --profile e2 https://key:secret@s3.example.com ls e2:
ss3 --profile e2 https://s3.example.com ls e2: --format json
```

**List objects in bucket:**
```bash
ss3 --profile e2 https://s3.example.com ls e2:mybucket/prefix
```

**Copy local file to S3:**
```bash
ss3 --profile e2 https://s3.example.com cp ./file.txt e2:mybucket/dir/
```

**Download from S3:**
```bash
SS3_E2_ACCESS_KEY=xxx SS3_E2_SECRET_KEY=yyy \
ss3 --profile e2 https://s3.example.com cp e2:mybucket/file.txt ./local.txt
```

## Testing

Tests use Swift Testing framework (not XCTest).

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

### Test Coverage

Unit tests:
- GlobalOptions flag/environment resolution
- OutputFormatter implementations (Human, JSON, TSV)
- S3Path parsing for local and remote paths
- SigV4 signature generation

Integration tests (via minio):
- Bucket operations (create, delete, list)
- Object operations (put, get, head, delete, copy, list)
- Multipart uploads
- CLI ls command (buckets, objects, formats)
- CLI cp command (upload, download, multipart)
