# SwiftS3 Framework Design

A Swift framework for communicating with S3-compatible APIs (AWS S3, Backblaze B2, Cloudflare R2, Google Cloud Storage).

## Requirements

- Swift 6.2 with strict concurrency
- Cross-platform: macOS/iOS 26+ and Linux (Swift Static SDK)
- No external dependencies
- All network/disk functions async
- Swift Package Manager
- Comprehensive tests via Swift Test
- SwiftLint

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| API surface | Single `S3Client` class | Simple, matches AWS SDK patterns |
| Error handling | Typed hierarchy | Distinguish API vs network vs parsing errors |
| Large objects | Dual API (Data + AsyncBytes) | Convenience for small files, streaming for large |
| Configuration | `S3Configuration` + provider extensions | Clean init, testable, extensible |
| XML parsing | Foundation `XMLParser` | Only cross-platform option |

## Package Structure

```
SwiftS3/
├── Package.swift
├── Sources/
│   └── SwiftS3/
│       ├── S3Client.swift
│       ├── Configuration/
│       │   ├── S3Configuration.swift
│       │   └── S3Configuration+Providers.swift
│       ├── Models/
│       │   ├── Bucket.swift
│       │   ├── S3Object.swift
│       │   ├── ObjectMetadata.swift
│       │   ├── Owner.swift
│       │   ├── MultipartUpload.swift
│       │   ├── Part.swift
│       │   └── CompletedPart.swift
│       ├── Results/
│       │   ├── ListBucketsResult.swift
│       │   ├── ListObjectsResult.swift
│       │   ├── ListMultipartUploadsResult.swift
│       │   └── ListPartsResult.swift
│       ├── Errors/
│       │   ├── S3Error.swift
│       │   ├── S3APIError.swift
│       │   ├── S3NetworkError.swift
│       │   └── S3ParsingError.swift
│       ├── Auth/
│       │   └── SigV4Signer.swift
│       ├── Internal/
│       │   ├── XMLResponseParser.swift
│       │   ├── HTTPClient.swift
│       │   └── RequestBuilder.swift
│       └── Extensions/
│           └── Data+Hex.swift
└── Tests/
    └── SwiftS3Tests/
        ├── SigV4SignerTests.swift
        ├── XMLParserTests.swift
        ├── ConfigurationTests.swift
        ├── RequestBuilderTests.swift
        ├── S3ClientTests.swift
        └── S3LiveTests.swift
```

## Public API

### Configuration

```swift
public struct S3Configuration: Sendable {
    public let accessKeyId: String
    public let secretAccessKey: String
    public let region: String
    public let endpoint: URL
    public let usePathStyleAddressing: Bool

    public init(
        accessKeyId: String,
        secretAccessKey: String,
        region: String,
        endpoint: URL,
        usePathStyleAddressing: Bool = false
    )
}

// Provider convenience initializers
extension S3Configuration {
    public static func aws(
        accessKeyId: String,
        secretAccessKey: String,
        region: String
    ) -> S3Configuration

    public static func backblaze(
        accessKeyId: String,
        secretAccessKey: String,
        region: String
    ) -> S3Configuration

    public static func cloudflare(
        accessKeyId: String,
        secretAccessKey: String,
        accountId: String
    ) -> S3Configuration

    public static func gcs(
        accessKeyId: String,
        secretAccessKey: String
    ) -> S3Configuration
}
```

### Error Types

```swift
public protocol S3Error: Error, Sendable {
    var message: String { get }
}

public struct S3APIError: S3Error {
    public let code: Code
    public let message: String
    public let resource: String?
    public let requestId: String?

    public enum Code: String, Sendable {
        case accessDenied = "AccessDenied"
        case bucketAlreadyExists = "BucketAlreadyExists"
        case bucketNotEmpty = "BucketNotEmpty"
        case invalidBucketName = "InvalidBucketName"
        case noSuchBucket = "NoSuchBucket"
        case noSuchKey = "NoSuchKey"
        case noSuchUpload = "NoSuchUpload"
        case preconditionFailed = "PreconditionFailed"
        case invalidRequest = "InvalidRequest"
        case invalidPart = "InvalidPart"
        case invalidPartOrder = "InvalidPartOrder"
        case unknown
    }
}

public struct S3NetworkError: S3Error {
    public let message: String
    public let underlyingError: Error?
}

public struct S3ParsingError: S3Error {
    public let message: String
    public let responseBody: String?
}
```

### Model Types

```swift
public struct Owner: Sendable, Equatable {
    public let id: String
    public let displayName: String?
}

public struct Bucket: Sendable, Equatable {
    public let name: String
    public let creationDate: Date?
    public let region: String?
}

public struct S3Object: Sendable, Equatable {
    public let key: String
    public let lastModified: Date?
    public let etag: String?
    public let size: Int64?
    public let storageClass: String?
    public let owner: Owner?
}

public struct ObjectMetadata: Sendable {
    public let contentLength: Int64
    public let contentType: String?
    public let etag: String?
    public let lastModified: Date?
    public let versionId: String?
    public let metadata: [String: String]
}

public struct MultipartUpload: Sendable {
    public let uploadId: String
    public let key: String
    public let initiated: Date?
}

public struct Part: Sendable {
    public let partNumber: Int
    public let etag: String
    public let size: Int64?
    public let lastModified: Date?
}

public struct CompletedPart: Sendable {
    public let partNumber: Int
    public let etag: String
}
```

### Result Types

```swift
public struct ListBucketsResult: Sendable {
    public let buckets: [Bucket]
    public let owner: Owner?
    public let continuationToken: String?
}

public struct ListObjectsResult: Sendable {
    public let objects: [S3Object]
    public let commonPrefixes: [String]
    public let isTruncated: Bool
    public let continuationToken: String?
}

public struct ListMultipartUploadsResult: Sendable {
    public let uploads: [MultipartUpload]
    public let isTruncated: Bool
    public let nextKeyMarker: String?
    public let nextUploadIdMarker: String?
}

public struct ListPartsResult: Sendable {
    public let parts: [Part]
    public let isTruncated: Bool
    public let nextPartNumberMarker: Int?
}
```

### S3Client

```swift
public final class S3Client: Sendable {
    public init(configuration: S3Configuration)

    // MARK: - Bucket Operations

    public func listBuckets(
        prefix: String? = nil,
        maxBuckets: Int? = nil,
        continuationToken: String? = nil
    ) async throws -> ListBucketsResult

    public func createBucket(_ name: String, region: String? = nil) async throws

    public func deleteBucket(_ name: String) async throws

    public func headBucket(_ name: String) async throws -> String?

    // MARK: - Object Operations

    public func listObjects(
        bucket: String,
        prefix: String? = nil,
        delimiter: String? = nil,
        maxKeys: Int? = nil,
        continuationToken: String? = nil
    ) async throws -> ListObjectsResult

    public func getObject(
        bucket: String,
        key: String,
        range: Range<Int64>? = nil
    ) async throws -> (data: Data, metadata: ObjectMetadata)

    public func getObjectStream(
        bucket: String,
        key: String,
        range: Range<Int64>? = nil
    ) async throws -> (stream: AsyncThrowingStream<UInt8, Error>, metadata: ObjectMetadata)

    public func putObject(
        bucket: String,
        key: String,
        data: Data,
        contentType: String? = nil,
        metadata: [String: String]? = nil
    ) async throws -> String

    public func deleteObject(bucket: String, key: String) async throws

    public func headObject(bucket: String, key: String) async throws -> ObjectMetadata

    public func copyObject(
        sourceBucket: String,
        sourceKey: String,
        destinationBucket: String,
        destinationKey: String
    ) async throws -> String

    // MARK: - Multipart Upload Operations

    public func createMultipartUpload(
        bucket: String,
        key: String,
        contentType: String? = nil,
        metadata: [String: String]? = nil
    ) async throws -> MultipartUpload

    public func uploadPart(
        bucket: String,
        key: String,
        uploadId: String,
        partNumber: Int,
        data: Data
    ) async throws -> CompletedPart

    public func completeMultipartUpload(
        bucket: String,
        key: String,
        uploadId: String,
        parts: [CompletedPart]
    ) async throws -> String

    public func abortMultipartUpload(
        bucket: String,
        key: String,
        uploadId: String
    ) async throws

    public func listMultipartUploads(
        bucket: String,
        prefix: String? = nil,
        maxUploads: Int? = nil
    ) async throws -> ListMultipartUploadsResult

    public func listParts(
        bucket: String,
        key: String,
        uploadId: String,
        maxParts: Int? = nil,
        partNumberMarker: Int? = nil
    ) async throws -> ListPartsResult
}
```

## Internal Components

### SigV4Signer

AWS Signature Version 4 implementation:

```swift
internal struct SigV4Signer: Sendable {
    let accessKeyId: String
    let secretAccessKey: String
    let region: String
    let service: String = "s3"

    func sign(
        request: inout URLRequest,
        date: Date = Date(),
        payloadHash: String
    )

    func canonicalRequest(_ request: URLRequest, payloadHash: String) -> String
    func stringToSign(_ canonicalRequest: String, date: Date) -> String
    func signingKey(date: Date) -> Data
    func signature(_ stringToSign: String, key: Data) -> String
}
```

### XMLResponseParser

Wraps Foundation's `XMLParser` for async-friendly use:

```swift
internal final class XMLResponseParser: NSObject, XMLParserDelegate {
    func parse<T: XMLParseable>(_ data: Data) throws -> T
}

internal protocol XMLParseable {
    init(from parser: XMLParserHelper) throws
}
```

### HTTPClient

Thin wrapper around URLSession:

```swift
internal struct HTTPClient: Sendable {
    let session: URLSession

    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)

    func executeStream(
        _ request: URLRequest
    ) async throws -> (AsyncThrowingStream<UInt8, Error>, HTTPURLResponse)
}
```

### RequestBuilder

Constructs URLRequests for S3 operations:

```swift
internal struct RequestBuilder: Sendable {
    let configuration: S3Configuration
    let signer: SigV4Signer

    func buildRequest(
        method: String,
        bucket: String?,
        key: String?,
        queryItems: [URLQueryItem]?,
        headers: [String: String]?,
        body: Data?
    ) -> URLRequest
}
```

## Testing Strategy

### Unit Tests (no network)

- **SigV4SignerTests**: Test against AWS test vectors
- **XMLParserTests**: Parse sample responses, test error handling
- **ConfigurationTests**: Test provider initializers, URL construction
- **RequestBuilderTests**: Test URL/header generation

### Integration Tests (mock HTTP)

- **S3ClientTests**: Inject mock HTTPClient, test each operation's flow

### Live Tests (optional)

- **S3LiveTests**: Full round-trip against real S3/MinIO
- Skipped by default, enabled via `S3_TEST_CREDENTIALS` environment variable

## S3 Operations Covered

| Category | Operations |
|----------|------------|
| Bucket | ListBuckets, CreateBucket, DeleteBucket, HeadBucket |
| Object | GetObject, PutObject, DeleteObject, HeadObject, ListObjectsV2, CopyObject |
| Multipart | CreateMultipartUpload, UploadPart, CompleteMultipartUpload, AbortMultipartUpload, ListMultipartUploads, ListParts |

Total: 16 operations
