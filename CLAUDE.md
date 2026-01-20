# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
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

## Project Constraints

- Swift 6.2.x with strict concurrency enabled
- Cross-platform: macOS 26+ and Linux (Swift Static Linux SDK)
- No external dependencies - pure Swift implementation
- All public types must be `Sendable`

## Architecture

SwiftS3 is a pure Swift S3-compatible API client supporting AWS S3, Backblaze B2, Cloudflare R2, and Google Cloud Storage.

### Core Components

**S3Client** (`Sources/SwiftS3/S3Client.swift`): Main public API providing 16 S3 operations (bucket CRUD, object CRUD, multipart uploads). All operations are `async throws`.

**SigV4Signer** (`Sources/SwiftS3/Auth/SigV4Signer.swift`): AWS Signature Version 4 implementation using pure Swift SHA256/HMAC-SHA256 (in `Extensions/Crypto.swift`).

**XMLResponseParser** (`Sources/SwiftS3/Internal/XMLResponseParser.swift`): Uses Foundation's `XMLParser` with separate delegate classes per response type to avoid shared state issues.

**RequestBuilder** (`Sources/SwiftS3/Internal/RequestBuilder.swift`): Constructs URLs and headers, supporting both virtual-hosted (AWS) and path-style (Backblaze/Cloudflare/GCS) addressing.

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

## Testing

Tests use Swift Testing framework (not XCTest). Unit tests mock `HTTPClient`; live tests require `S3_TEST_CREDENTIALS` environment variable and are skipped by default.
