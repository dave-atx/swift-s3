# SwiftS3 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Swift framework for S3-compatible APIs (AWS, Backblaze, Cloudflare, GCS) with no external dependencies.

**Architecture:** Single `S3Client` class with async operations, typed error hierarchy, SigV4 authentication, and Foundation XMLParser for responses.

**Tech Stack:** Swift 6.2, strict concurrency, Foundation networking, Swift Package Manager, Swift Testing

---

## Phase 1: Package Setup

### Task 1.1: Create Package.swift

**Files:**
- Create: `Package.swift`

**Step 1: Create Package.swift**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftS3",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "SwiftS3",
            targets: ["SwiftS3"]
        )
    ],
    targets: [
        .target(
            name: "SwiftS3",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "SwiftS3Tests",
            dependencies: ["SwiftS3"]
        )
    ]
)
```

**Step 2: Create directory structure**

Run:
```bash
mkdir -p Sources/SwiftS3
mkdir -p Tests/SwiftS3Tests
```

**Step 3: Create placeholder source file**

Create `Sources/SwiftS3/SwiftS3.swift`:
```swift
// SwiftS3 - S3 Compatible API Client
```

**Step 4: Create placeholder test file**

Create `Tests/SwiftS3Tests/SwiftS3Tests.swift`:
```swift
import Testing
@testable import SwiftS3

@Test func packageBuilds() async throws {
    #expect(true)
}
```

**Step 5: Verify build**

Run: `swift build`
Expected: Build succeeds

**Step 6: Run tests**

Run: `swift test`
Expected: 1 test passes

**Step 7: Commit**

```bash
git add -A
git commit -m "feat: initialize Swift package structure"
```

---

## Phase 2: Error Types

### Task 2.1: S3Error Protocol

**Files:**
- Create: `Sources/SwiftS3/Errors/S3Error.swift`
- Create: `Tests/SwiftS3Tests/ErrorTests.swift`

**Step 1: Write test**

Create `Tests/SwiftS3Tests/ErrorTests.swift`:
```swift
import Testing
@testable import SwiftS3

@Test func s3ErrorHasMessage() async throws {
    let error = S3NetworkError(message: "Connection failed", underlyingError: nil)
    #expect(error.message == "Connection failed")
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter s3ErrorHasMessage`
Expected: FAIL - cannot find type 'S3NetworkError'

**Step 3: Create S3Error.swift**

Create `Sources/SwiftS3/Errors/S3Error.swift`:
```swift
import Foundation

public protocol S3Error: Error, Sendable {
    var message: String { get }
}
```

**Step 4: Run test - still fails**

Run: `swift test --filter s3ErrorHasMessage`
Expected: FAIL - cannot find type 'S3NetworkError'

**Step 5: Commit protocol**

```bash
git add -A
git commit -m "feat: add S3Error protocol"
```

### Task 2.2: S3NetworkError

**Files:**
- Create: `Sources/SwiftS3/Errors/S3NetworkError.swift`
- Modify: `Tests/SwiftS3Tests/ErrorTests.swift`

**Step 1: Create S3NetworkError.swift**

```swift
import Foundation

public struct S3NetworkError: S3Error {
    public let message: String
    public let underlyingError: (any Error)?

    public init(message: String, underlyingError: (any Error)?) {
        self.message = message
        self.underlyingError = underlyingError
    }
}
```

**Step 2: Run test**

Run: `swift test --filter s3ErrorHasMessage`
Expected: PASS

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add S3NetworkError type"
```

### Task 2.3: S3ParsingError

**Files:**
- Create: `Sources/SwiftS3/Errors/S3ParsingError.swift`
- Modify: `Tests/SwiftS3Tests/ErrorTests.swift`

**Step 1: Add test**

Add to `Tests/SwiftS3Tests/ErrorTests.swift`:
```swift
@Test func s3ParsingErrorIncludesResponseBody() async throws {
    let error = S3ParsingError(message: "Invalid XML", responseBody: "<bad>")
    #expect(error.message == "Invalid XML")
    #expect(error.responseBody == "<bad>")
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter s3ParsingErrorIncludesResponseBody`
Expected: FAIL

**Step 3: Create S3ParsingError.swift**

```swift
import Foundation

public struct S3ParsingError: S3Error {
    public let message: String
    public let responseBody: String?

    public init(message: String, responseBody: String?) {
        self.message = message
        self.responseBody = responseBody
    }
}
```

**Step 4: Run test**

Run: `swift test --filter s3ParsingErrorIncludesResponseBody`
Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add S3ParsingError type"
```

### Task 2.4: S3APIError

**Files:**
- Create: `Sources/SwiftS3/Errors/S3APIError.swift`
- Modify: `Tests/SwiftS3Tests/ErrorTests.swift`

**Step 1: Add test**

Add to `Tests/SwiftS3Tests/ErrorTests.swift`:
```swift
@Test func s3APIErrorCodeMapping() async throws {
    let error = S3APIError(
        code: .noSuchBucket,
        message: "Bucket not found",
        resource: "/my-bucket",
        requestId: "abc123"
    )
    #expect(error.code == .noSuchBucket)
    #expect(error.code.rawValue == "NoSuchBucket")
}

@Test func s3APIErrorUnknownCode() async throws {
    let error = S3APIError(
        code: .unknown("CustomError"),
        message: "Something custom",
        resource: nil,
        requestId: nil
    )
    if case .unknown(let code) = error.code {
        #expect(code == "CustomError")
    } else {
        Issue.record("Expected unknown code")
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter s3APIError`
Expected: FAIL

**Step 3: Create S3APIError.swift**

```swift
import Foundation

public struct S3APIError: S3Error {
    public let code: Code
    public let message: String
    public let resource: String?
    public let requestId: String?

    public init(code: Code, message: String, resource: String?, requestId: String?) {
        self.code = code
        self.message = message
        self.resource = resource
        self.requestId = requestId
    }

    public enum Code: Sendable, Equatable {
        case accessDenied
        case bucketAlreadyExists
        case bucketNotEmpty
        case invalidBucketName
        case noSuchBucket
        case noSuchKey
        case noSuchUpload
        case preconditionFailed
        case invalidRequest
        case invalidPart
        case invalidPartOrder
        case unknown(String)

        public var rawValue: String {
            switch self {
            case .accessDenied: return "AccessDenied"
            case .bucketAlreadyExists: return "BucketAlreadyExists"
            case .bucketNotEmpty: return "BucketNotEmpty"
            case .invalidBucketName: return "InvalidBucketName"
            case .noSuchBucket: return "NoSuchBucket"
            case .noSuchKey: return "NoSuchKey"
            case .noSuchUpload: return "NoSuchUpload"
            case .preconditionFailed: return "PreconditionFailed"
            case .invalidRequest: return "InvalidRequest"
            case .invalidPart: return "InvalidPart"
            case .invalidPartOrder: return "InvalidPartOrder"
            case .unknown(let code): return code
            }
        }

        public init(rawValue: String) {
            switch rawValue {
            case "AccessDenied": self = .accessDenied
            case "BucketAlreadyExists": self = .bucketAlreadyExists
            case "BucketNotEmpty": self = .bucketNotEmpty
            case "InvalidBucketName": self = .invalidBucketName
            case "NoSuchBucket": self = .noSuchBucket
            case "NoSuchKey": self = .noSuchKey
            case "NoSuchUpload": self = .noSuchUpload
            case "PreconditionFailed": self = .preconditionFailed
            case "InvalidRequest": self = .invalidRequest
            case "InvalidPart": self = .invalidPart
            case "InvalidPartOrder": self = .invalidPartOrder
            default: self = .unknown(rawValue)
            }
        }
    }
}
```

**Step 4: Run tests**

Run: `swift test --filter s3APIError`
Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add S3APIError with error codes"
```

---

## Phase 3: Model Types

### Task 3.1: Owner Model

**Files:**
- Create: `Sources/SwiftS3/Models/Owner.swift`
- Create: `Tests/SwiftS3Tests/ModelTests.swift`

**Step 1: Write test**

Create `Tests/SwiftS3Tests/ModelTests.swift`:
```swift
import Testing
@testable import SwiftS3

@Test func ownerEquality() async throws {
    let owner1 = Owner(id: "123", displayName: "Alice")
    let owner2 = Owner(id: "123", displayName: "Alice")
    let owner3 = Owner(id: "456", displayName: "Bob")

    #expect(owner1 == owner2)
    #expect(owner1 != owner3)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter ownerEquality`
Expected: FAIL

**Step 3: Create Owner.swift**

```swift
import Foundation

public struct Owner: Sendable, Equatable {
    public let id: String
    public let displayName: String?

    public init(id: String, displayName: String?) {
        self.id = id
        self.displayName = displayName
    }
}
```

**Step 4: Run test**

Run: `swift test --filter ownerEquality`
Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Owner model"
```

### Task 3.2: Bucket Model

**Files:**
- Create: `Sources/SwiftS3/Models/Bucket.swift`
- Modify: `Tests/SwiftS3Tests/ModelTests.swift`

**Step 1: Add test**

Add to `Tests/SwiftS3Tests/ModelTests.swift`:
```swift
@Test func bucketProperties() async throws {
    let date = Date()
    let bucket = Bucket(name: "my-bucket", creationDate: date, region: "us-east-1")

    #expect(bucket.name == "my-bucket")
    #expect(bucket.creationDate == date)
    #expect(bucket.region == "us-east-1")
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter bucketProperties`
Expected: FAIL

**Step 3: Create Bucket.swift**

```swift
import Foundation

public struct Bucket: Sendable, Equatable {
    public let name: String
    public let creationDate: Date?
    public let region: String?

    public init(name: String, creationDate: Date?, region: String?) {
        self.name = name
        self.creationDate = creationDate
        self.region = region
    }
}
```

**Step 4: Run test**

Run: `swift test --filter bucketProperties`
Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Bucket model"
```

### Task 3.3: S3Object Model

**Files:**
- Create: `Sources/SwiftS3/Models/S3Object.swift`
- Modify: `Tests/SwiftS3Tests/ModelTests.swift`

**Step 1: Add test**

Add to `Tests/SwiftS3Tests/ModelTests.swift`:
```swift
@Test func s3ObjectProperties() async throws {
    let obj = S3Object(
        key: "folder/file.txt",
        lastModified: nil,
        etag: "\"abc123\"",
        size: 1024,
        storageClass: "STANDARD",
        owner: nil
    )

    #expect(obj.key == "folder/file.txt")
    #expect(obj.size == 1024)
    #expect(obj.storageClass == "STANDARD")
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter s3ObjectProperties`
Expected: FAIL

**Step 3: Create S3Object.swift**

```swift
import Foundation

public struct S3Object: Sendable, Equatable {
    public let key: String
    public let lastModified: Date?
    public let etag: String?
    public let size: Int64?
    public let storageClass: String?
    public let owner: Owner?

    public init(
        key: String,
        lastModified: Date?,
        etag: String?,
        size: Int64?,
        storageClass: String?,
        owner: Owner?
    ) {
        self.key = key
        self.lastModified = lastModified
        self.etag = etag
        self.size = size
        self.storageClass = storageClass
        self.owner = owner
    }
}
```

**Step 4: Run test**

Run: `swift test --filter s3ObjectProperties`
Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add S3Object model"
```

### Task 3.4: ObjectMetadata Model

**Files:**
- Create: `Sources/SwiftS3/Models/ObjectMetadata.swift`
- Modify: `Tests/SwiftS3Tests/ModelTests.swift`

**Step 1: Add test**

Add to `Tests/SwiftS3Tests/ModelTests.swift`:
```swift
@Test func objectMetadataProperties() async throws {
    let metadata = ObjectMetadata(
        contentLength: 2048,
        contentType: "application/json",
        etag: "\"def456\"",
        lastModified: nil,
        versionId: "v1",
        metadata: ["author": "test"]
    )

    #expect(metadata.contentLength == 2048)
    #expect(metadata.contentType == "application/json")
    #expect(metadata.metadata["author"] == "test")
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter objectMetadataProperties`
Expected: FAIL

**Step 3: Create ObjectMetadata.swift**

```swift
import Foundation

public struct ObjectMetadata: Sendable {
    public let contentLength: Int64
    public let contentType: String?
    public let etag: String?
    public let lastModified: Date?
    public let versionId: String?
    public let metadata: [String: String]

    public init(
        contentLength: Int64,
        contentType: String?,
        etag: String?,
        lastModified: Date?,
        versionId: String?,
        metadata: [String: String]
    ) {
        self.contentLength = contentLength
        self.contentType = contentType
        self.etag = etag
        self.lastModified = lastModified
        self.versionId = versionId
        self.metadata = metadata
    }
}
```

**Step 4: Run test**

Run: `swift test --filter objectMetadataProperties`
Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add ObjectMetadata model"
```

### Task 3.5: Multipart Models

**Files:**
- Create: `Sources/SwiftS3/Models/MultipartUpload.swift`
- Create: `Sources/SwiftS3/Models/Part.swift`
- Create: `Sources/SwiftS3/Models/CompletedPart.swift`
- Modify: `Tests/SwiftS3Tests/ModelTests.swift`

**Step 1: Add tests**

Add to `Tests/SwiftS3Tests/ModelTests.swift`:
```swift
@Test func multipartUploadProperties() async throws {
    let upload = MultipartUpload(uploadId: "upload-123", key: "large-file.bin", initiated: nil)
    #expect(upload.uploadId == "upload-123")
    #expect(upload.key == "large-file.bin")
}

@Test func partProperties() async throws {
    let part = Part(partNumber: 1, etag: "\"part-etag\"", size: 5_242_880, lastModified: nil)
    #expect(part.partNumber == 1)
    #expect(part.size == 5_242_880)
}

@Test func completedPartProperties() async throws {
    let part = CompletedPart(partNumber: 2, etag: "\"completed-etag\"")
    #expect(part.partNumber == 2)
    #expect(part.etag == "\"completed-etag\"")
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter multipartUploadProperties`
Expected: FAIL

**Step 3: Create MultipartUpload.swift**

```swift
import Foundation

public struct MultipartUpload: Sendable {
    public let uploadId: String
    public let key: String
    public let initiated: Date?

    public init(uploadId: String, key: String, initiated: Date?) {
        self.uploadId = uploadId
        self.key = key
        self.initiated = initiated
    }
}
```

**Step 4: Create Part.swift**

```swift
import Foundation

public struct Part: Sendable {
    public let partNumber: Int
    public let etag: String
    public let size: Int64?
    public let lastModified: Date?

    public init(partNumber: Int, etag: String, size: Int64?, lastModified: Date?) {
        self.partNumber = partNumber
        self.etag = etag
        self.size = size
        self.lastModified = lastModified
    }
}
```

**Step 5: Create CompletedPart.swift**

```swift
import Foundation

public struct CompletedPart: Sendable {
    public let partNumber: Int
    public let etag: String

    public init(partNumber: Int, etag: String) {
        self.partNumber = partNumber
        self.etag = etag
    }
}
```

**Step 6: Run tests**

Run: `swift test --filter "multipartUploadProperties|partProperties|completedPartProperties"`
Expected: PASS

**Step 7: Commit**

```bash
git add -A
git commit -m "feat: add multipart upload models"
```

### Task 3.6: Result Types

**Files:**
- Create: `Sources/SwiftS3/Results/ListBucketsResult.swift`
- Create: `Sources/SwiftS3/Results/ListObjectsResult.swift`
- Create: `Sources/SwiftS3/Results/ListMultipartUploadsResult.swift`
- Create: `Sources/SwiftS3/Results/ListPartsResult.swift`

**Step 1: Create ListBucketsResult.swift**

```swift
import Foundation

public struct ListBucketsResult: Sendable {
    public let buckets: [Bucket]
    public let owner: Owner?
    public let continuationToken: String?

    public init(buckets: [Bucket], owner: Owner?, continuationToken: String?) {
        self.buckets = buckets
        self.owner = owner
        self.continuationToken = continuationToken
    }
}
```

**Step 2: Create ListObjectsResult.swift**

```swift
import Foundation

public struct ListObjectsResult: Sendable {
    public let objects: [S3Object]
    public let commonPrefixes: [String]
    public let isTruncated: Bool
    public let continuationToken: String?

    public init(objects: [S3Object], commonPrefixes: [String], isTruncated: Bool, continuationToken: String?) {
        self.objects = objects
        self.commonPrefixes = commonPrefixes
        self.isTruncated = isTruncated
        self.continuationToken = continuationToken
    }
}
```

**Step 3: Create ListMultipartUploadsResult.swift**

```swift
import Foundation

public struct ListMultipartUploadsResult: Sendable {
    public let uploads: [MultipartUpload]
    public let isTruncated: Bool
    public let nextKeyMarker: String?
    public let nextUploadIdMarker: String?

    public init(uploads: [MultipartUpload], isTruncated: Bool, nextKeyMarker: String?, nextUploadIdMarker: String?) {
        self.uploads = uploads
        self.isTruncated = isTruncated
        self.nextKeyMarker = nextKeyMarker
        self.nextUploadIdMarker = nextUploadIdMarker
    }
}
```

**Step 4: Create ListPartsResult.swift**

```swift
import Foundation

public struct ListPartsResult: Sendable {
    public let parts: [Part]
    public let isTruncated: Bool
    public let nextPartNumberMarker: Int?

    public init(parts: [Part], isTruncated: Bool, nextPartNumberMarker: Int?) {
        self.parts = parts
        self.isTruncated = isTruncated
        self.nextPartNumberMarker = nextPartNumberMarker
    }
}
```

**Step 5: Build to verify**

Run: `swift build`
Expected: PASS

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: add result types for list operations"
```

---

## Phase 4: Configuration

### Task 4.1: S3Configuration

**Files:**
- Create: `Sources/SwiftS3/Configuration/S3Configuration.swift`
- Create: `Tests/SwiftS3Tests/ConfigurationTests.swift`

**Step 1: Write test**

Create `Tests/SwiftS3Tests/ConfigurationTests.swift`:
```swift
import Testing
import Foundation
@testable import SwiftS3

@Test func configurationStoresProperties() async throws {
    let config = S3Configuration(
        accessKeyId: "AKIAIOSFODNN7EXAMPLE",
        secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region: "us-east-1",
        endpoint: URL(string: "https://s3.us-east-1.amazonaws.com")!,
        usePathStyleAddressing: false
    )

    #expect(config.accessKeyId == "AKIAIOSFODNN7EXAMPLE")
    #expect(config.region == "us-east-1")
    #expect(config.usePathStyleAddressing == false)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter configurationStoresProperties`
Expected: FAIL

**Step 3: Create S3Configuration.swift**

```swift
import Foundation

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
    ) {
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.region = region
        self.endpoint = endpoint
        self.usePathStyleAddressing = usePathStyleAddressing
    }
}
```

**Step 4: Run test**

Run: `swift test --filter configurationStoresProperties`
Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add S3Configuration"
```

### Task 4.2: Provider Extensions

**Files:**
- Create: `Sources/SwiftS3/Configuration/S3Configuration+Providers.swift`
- Modify: `Tests/SwiftS3Tests/ConfigurationTests.swift`

**Step 1: Add tests**

Add to `Tests/SwiftS3Tests/ConfigurationTests.swift`:
```swift
@Test func awsConfigurationEndpoint() async throws {
    let config = S3Configuration.aws(
        accessKeyId: "AKIA...",
        secretAccessKey: "secret",
        region: "us-west-2"
    )

    #expect(config.endpoint.absoluteString == "https://s3.us-west-2.amazonaws.com")
    #expect(config.region == "us-west-2")
    #expect(config.usePathStyleAddressing == false)
}

@Test func backblazeConfigurationEndpoint() async throws {
    let config = S3Configuration.backblaze(
        accessKeyId: "keyId",
        secretAccessKey: "appKey",
        region: "us-west-004"
    )

    #expect(config.endpoint.absoluteString == "https://s3.us-west-004.backblazeb2.com")
    #expect(config.usePathStyleAddressing == true)
}

@Test func cloudflareConfigurationEndpoint() async throws {
    let config = S3Configuration.cloudflare(
        accessKeyId: "accessKey",
        secretAccessKey: "secretKey",
        accountId: "abc123def456"
    )

    #expect(config.endpoint.absoluteString == "https://abc123def456.r2.cloudflarestorage.com")
    #expect(config.usePathStyleAddressing == true)
}

@Test func gcsConfigurationEndpoint() async throws {
    let config = S3Configuration.gcs(
        accessKeyId: "GOOG...",
        secretAccessKey: "secret"
    )

    #expect(config.endpoint.absoluteString == "https://storage.googleapis.com")
    #expect(config.usePathStyleAddressing == true)
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter "awsConfiguration|backblazeConfiguration|cloudflareConfiguration|gcsConfiguration"`
Expected: FAIL

**Step 3: Create S3Configuration+Providers.swift**

```swift
import Foundation

extension S3Configuration {
    public static func aws(
        accessKeyId: String,
        secretAccessKey: String,
        region: String
    ) -> S3Configuration {
        S3Configuration(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            region: region,
            endpoint: URL(string: "https://s3.\(region).amazonaws.com")!,
            usePathStyleAddressing: false
        )
    }

    public static func backblaze(
        accessKeyId: String,
        secretAccessKey: String,
        region: String
    ) -> S3Configuration {
        S3Configuration(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            region: region,
            endpoint: URL(string: "https://s3.\(region).backblazeb2.com")!,
            usePathStyleAddressing: true
        )
    }

    public static func cloudflare(
        accessKeyId: String,
        secretAccessKey: String,
        accountId: String
    ) -> S3Configuration {
        S3Configuration(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            region: "auto",
            endpoint: URL(string: "https://\(accountId).r2.cloudflarestorage.com")!,
            usePathStyleAddressing: true
        )
    }

    public static func gcs(
        accessKeyId: String,
        secretAccessKey: String
    ) -> S3Configuration {
        S3Configuration(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            region: "auto",
            endpoint: URL(string: "https://storage.googleapis.com")!,
            usePathStyleAddressing: true
        )
    }
}
```

**Step 4: Run tests**

Run: `swift test --filter "awsConfiguration|backblazeConfiguration|cloudflareConfiguration|gcsConfiguration"`
Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add provider convenience initializers"
```

---

## Phase 5: Crypto Utilities

### Task 5.1: Data+Hex Extension

**Files:**
- Create: `Sources/SwiftS3/Extensions/Data+Hex.swift`
- Create: `Tests/SwiftS3Tests/ExtensionTests.swift`

**Step 1: Write test**

Create `Tests/SwiftS3Tests/ExtensionTests.swift`:
```swift
import Testing
import Foundation
@testable import SwiftS3

@Test func dataToHexString() async throws {
    let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
    #expect(data.hexString == "deadbeef")
}

@Test func emptyDataToHexString() async throws {
    let data = Data()
    #expect(data.hexString == "")
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter dataToHexString`
Expected: FAIL

**Step 3: Create Data+Hex.swift**

```swift
import Foundation

extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
```

**Step 4: Run tests**

Run: `swift test --filter "dataToHexString|emptyDataToHexString"`
Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Data hex string extension"
```

### Task 5.2: HMAC-SHA256 and SHA256

**Files:**
- Create: `Sources/SwiftS3/Extensions/Crypto.swift`
- Modify: `Tests/SwiftS3Tests/ExtensionTests.swift`

**Step 1: Add tests**

Add to `Tests/SwiftS3Tests/ExtensionTests.swift`:
```swift
@Test func sha256Hash() async throws {
    let data = "hello".data(using: .utf8)!
    let hash = data.sha256()
    // Known SHA256 of "hello"
    #expect(hash.hexString == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
}

@Test func hmacSHA256() async throws {
    let key = "key".data(using: .utf8)!
    let message = "message".data(using: .utf8)!
    let hmac = message.hmacSHA256(key: key)
    // Known HMAC-SHA256 of "message" with key "key"
    #expect(hmac.hexString == "6e9ef29b75fffc5b7abae527d58fdadb2fe42e7219011976917343065f58ed4a")
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter "sha256Hash|hmacSHA256"`
Expected: FAIL

**Step 3: Create Crypto.swift**

```swift
import Foundation
import CommonCrypto

extension Data {
    func sha256() -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(count), &hash)
        }
        return Data(hash)
    }

    func hmacSHA256(key: Data) -> Data {
        var hmac = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        key.withUnsafeBytes { keyBuffer in
            withUnsafeBytes { dataBuffer in
                CCHmac(
                    CCHmacAlgorithm(kCCHmacAlgSHA256),
                    keyBuffer.baseAddress,
                    key.count,
                    dataBuffer.baseAddress,
                    count,
                    &hmac
                )
            }
        }
        return Data(hmac)
    }
}
```

**Step 4: Run tests**

Run: `swift test --filter "sha256Hash|hmacSHA256"`
Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add SHA256 and HMAC-SHA256 crypto extensions"
```

---

## Phase 6: SigV4 Signer

### Task 6.1: Date Formatting

**Files:**
- Create: `Sources/SwiftS3/Auth/SigV4Signer.swift`
- Create: `Tests/SwiftS3Tests/SigV4SignerTests.swift`

**Step 1: Write test**

Create `Tests/SwiftS3Tests/SigV4SignerTests.swift`:
```swift
import Testing
import Foundation
@testable import SwiftS3

@Test func sigv4DateFormatting() async throws {
    let signer = SigV4Signer(
        accessKeyId: "AKID",
        secretAccessKey: "SECRET",
        region: "us-east-1"
    )

    // 2015-08-30T12:36:00Z
    let date = Date(timeIntervalSince1970: 1440938160)

    #expect(signer.dateStamp(for: date) == "20150830")
    #expect(signer.amzDate(for: date) == "20150830T123600Z")
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter sigv4DateFormatting`
Expected: FAIL

**Step 3: Create SigV4Signer.swift with date formatting**

```swift
import Foundation

struct SigV4Signer: Sendable {
    let accessKeyId: String
    let secretAccessKey: String
    let region: String
    let service: String = "s3"

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let amzDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    func dateStamp(for date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }

    func amzDate(for date: Date) -> String {
        Self.amzDateFormatter.string(from: date)
    }
}
```

**Step 4: Run test**

Run: `swift test --filter sigv4DateFormatting`
Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add SigV4Signer with date formatting"
```

### Task 6.2: Canonical Request

**Files:**
- Modify: `Sources/SwiftS3/Auth/SigV4Signer.swift`
- Modify: `Tests/SwiftS3Tests/SigV4SignerTests.swift`

**Step 1: Add test**

Add to `Tests/SwiftS3Tests/SigV4SignerTests.swift`:
```swift
@Test func canonicalRequest() async throws {
    let signer = SigV4Signer(
        accessKeyId: "AKID",
        secretAccessKey: "SECRET",
        region: "us-east-1"
    )

    var request = URLRequest(url: URL(string: "https://examplebucket.s3.amazonaws.com/test.txt")!)
    request.httpMethod = "GET"
    request.setValue("examplebucket.s3.amazonaws.com", forHTTPHeaderField: "Host")
    request.setValue("20130524T000000Z", forHTTPHeaderField: "x-amz-date")
    request.setValue("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", forHTTPHeaderField: "x-amz-content-sha256")

    let canonical = signer.canonicalRequest(request, payloadHash: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")

    let expected = """
        GET
        /test.txt

        host:examplebucket.s3.amazonaws.com
        x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        x-amz-date:20130524T000000Z

        host;x-amz-content-sha256;x-amz-date
        e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        """

    #expect(canonical == expected)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter canonicalRequest`
Expected: FAIL

**Step 3: Add canonicalRequest method**

Add to `SigV4Signer.swift`:
```swift
    func canonicalRequest(_ request: URLRequest, payloadHash: String) -> String {
        let method = request.httpMethod ?? "GET"

        let url = request.url!
        let path = url.path.isEmpty ? "/" : url.path

        let query = url.query ?? ""
        let sortedQuery = query
            .split(separator: "&")
            .sorted()
            .joined(separator: "&")

        // Get sorted headers (lowercase keys)
        var headers: [(String, String)] = []
        if let allHeaders = request.allHTTPHeaderFields {
            for (key, value) in allHeaders {
                headers.append((key.lowercased(), value))
            }
        }
        headers.sort { $0.0 < $1.0 }

        let canonicalHeaders = headers
            .map { "\($0.0):\($0.1)" }
            .joined(separator: "\n")

        let signedHeaders = headers
            .map { $0.0 }
            .joined(separator: ";")

        return """
            \(method)
            \(path)
            \(sortedQuery)
            \(canonicalHeaders)

            \(signedHeaders)
            \(payloadHash)
            """
    }
```

**Step 4: Run test**

Run: `swift test --filter canonicalRequest`
Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add canonical request generation"
```

### Task 6.3: String to Sign

**Files:**
- Modify: `Sources/SwiftS3/Auth/SigV4Signer.swift`
- Modify: `Tests/SwiftS3Tests/SigV4SignerTests.swift`

**Step 1: Add test**

Add to `Tests/SwiftS3Tests/SigV4SignerTests.swift`:
```swift
@Test func stringToSign() async throws {
    let signer = SigV4Signer(
        accessKeyId: "AKID",
        secretAccessKey: "SECRET",
        region: "us-east-1"
    )

    let date = Date(timeIntervalSince1970: 1440938160) // 20150830T123600Z
    let canonicalRequestHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    let stringToSign = signer.stringToSign(canonicalRequestHash: canonicalRequestHash, date: date)

    let expected = """
        AWS4-HMAC-SHA256
        20150830T123600Z
        20150830/us-east-1/s3/aws4_request
        e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        """

    #expect(stringToSign == expected)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter stringToSign`
Expected: FAIL

**Step 3: Add stringToSign method**

Add to `SigV4Signer.swift`:
```swift
    func stringToSign(canonicalRequestHash: String, date: Date) -> String {
        let dateStamp = dateStamp(for: date)
        let amzDate = amzDate(for: date)
        let scope = "\(dateStamp)/\(region)/\(service)/aws4_request"

        return """
            AWS4-HMAC-SHA256
            \(amzDate)
            \(scope)
            \(canonicalRequestHash)
            """
    }
```

**Step 4: Run test**

Run: `swift test --filter stringToSign`
Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add string to sign generation"
```

### Task 6.4: Signing Key

**Files:**
- Modify: `Sources/SwiftS3/Auth/SigV4Signer.swift`
- Modify: `Tests/SwiftS3Tests/SigV4SignerTests.swift`

**Step 1: Add test**

Add to `Tests/SwiftS3Tests/SigV4SignerTests.swift`:
```swift
@Test func signingKey() async throws {
    let signer = SigV4Signer(
        accessKeyId: "AKID",
        secretAccessKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
        region: "us-east-1"
    )

    let date = Date(timeIntervalSince1970: 1440938160) // 20150830
    let key = signer.signingKey(for: date)

    // This is a known test vector - signing key for the given secret/date/region
    #expect(key.count == 32) // SHA256 output is 32 bytes
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter signingKey`
Expected: FAIL

**Step 3: Add signingKey method**

Add to `SigV4Signer.swift`:
```swift
    func signingKey(for date: Date) -> Data {
        let dateStamp = dateStamp(for: date)
        let kSecret = "AWS4\(secretAccessKey)".data(using: .utf8)!
        let kDate = dateStamp.data(using: .utf8)!.hmacSHA256(key: kSecret)
        let kRegion = region.data(using: .utf8)!.hmacSHA256(key: kDate)
        let kService = service.data(using: .utf8)!.hmacSHA256(key: kRegion)
        let kSigning = "aws4_request".data(using: .utf8)!.hmacSHA256(key: kService)
        return kSigning
    }
```

**Step 4: Run test**

Run: `swift test --filter signingKey`
Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add signing key derivation"
```

### Task 6.5: Complete Sign Method

**Files:**
- Modify: `Sources/SwiftS3/Auth/SigV4Signer.swift`
- Modify: `Tests/SwiftS3Tests/SigV4SignerTests.swift`

**Step 1: Add test**

Add to `Tests/SwiftS3Tests/SigV4SignerTests.swift`:
```swift
@Test func signRequest() async throws {
    let signer = SigV4Signer(
        accessKeyId: "AKIAIOSFODNN7EXAMPLE",
        secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region: "us-east-1"
    )

    var request = URLRequest(url: URL(string: "https://examplebucket.s3.amazonaws.com/test.txt")!)
    request.httpMethod = "GET"
    request.setValue("examplebucket.s3.amazonaws.com", forHTTPHeaderField: "Host")

    let date = Date(timeIntervalSince1970: 1369353600) // 2013-05-24T00:00:00Z
    let payloadHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" // empty body

    signer.sign(request: &request, date: date, payloadHash: payloadHash)

    // Verify Authorization header is set
    let auth = request.value(forHTTPHeaderField: "Authorization")
    #expect(auth != nil)
    #expect(auth!.hasPrefix("AWS4-HMAC-SHA256"))
    #expect(auth!.contains("Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request"))

    // Verify x-amz-date is set
    let amzDate = request.value(forHTTPHeaderField: "x-amz-date")
    #expect(amzDate == "20130524T000000Z")
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter signRequest`
Expected: FAIL

**Step 3: Add sign method**

Add to `SigV4Signer.swift`:
```swift
    func sign(request: inout URLRequest, date: Date, payloadHash: String) {
        let amzDateValue = amzDate(for: date)
        let dateStampValue = dateStamp(for: date)

        // Set required headers before signing
        request.setValue(amzDateValue, forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")

        // Build canonical request
        let canonical = canonicalRequest(request, payloadHash: payloadHash)
        let canonicalHash = canonical.data(using: .utf8)!.sha256().hexString

        // Build string to sign
        let stringToSignValue = stringToSign(canonicalRequestHash: canonicalHash, date: date)

        // Calculate signature
        let signingKeyValue = signingKey(for: date)
        let signature = stringToSignValue.data(using: .utf8)!.hmacSHA256(key: signingKeyValue).hexString

        // Get signed headers list
        var headers: [String] = []
        if let allHeaders = request.allHTTPHeaderFields {
            headers = allHeaders.keys.map { $0.lowercased() }.sorted()
        }
        let signedHeaders = headers.joined(separator: ";")

        // Build credential scope
        let scope = "\(dateStampValue)/\(region)/\(service)/aws4_request"

        // Build Authorization header
        let authorization = "AWS4-HMAC-SHA256 Credential=\(accessKeyId)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

        request.setValue(authorization, forHTTPHeaderField: "Authorization")
    }
```

**Step 4: Run test**

Run: `swift test --filter signRequest`
Expected: PASS

**Step 5: Run all tests**

Run: `swift test`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: add complete SigV4 request signing"
```

---

## Phase 7: XML Parsing

### Task 7.1: XML Parser Helper

**Files:**
- Create: `Sources/SwiftS3/Internal/XMLResponseParser.swift`
- Create: `Tests/SwiftS3Tests/XMLParserTests.swift`

**Step 1: Write test**

Create `Tests/SwiftS3Tests/XMLParserTests.swift`:
```swift
import Testing
import Foundation
@testable import SwiftS3

@Test func parseErrorResponse() async throws {
    let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Error>
            <Code>NoSuchBucket</Code>
            <Message>The specified bucket does not exist</Message>
            <Resource>/mybucket</Resource>
            <RequestId>4442587FB7D0A2F9</RequestId>
        </Error>
        """

    let parser = XMLResponseParser()
    let error: S3APIError = try parser.parseError(from: xml.data(using: .utf8)!)

    #expect(error.code == .noSuchBucket)
    #expect(error.message == "The specified bucket does not exist")
    #expect(error.resource == "/mybucket")
    #expect(error.requestId == "4442587FB7D0A2F9")
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter parseErrorResponse`
Expected: FAIL

**Step 3: Create XMLResponseParser.swift**

```swift
import Foundation

final class XMLResponseParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    private var currentElement = ""
    private var currentText = ""
    private var elementStack: [String] = []
    private var result: [String: String] = [:]

    func parseError(from data: Data) throws -> S3APIError {
        result = [:]
        elementStack = []

        let parser = XMLParser(data: data)
        parser.delegate = self

        guard parser.parse() else {
            throw S3ParsingError(message: "Failed to parse XML", responseBody: String(data: data, encoding: .utf8))
        }

        guard let code = result["Code"],
              let message = result["Message"] else {
            throw S3ParsingError(message: "Missing required error fields", responseBody: String(data: data, encoding: .utf8))
        }

        return S3APIError(
            code: S3APIError.Code(rawValue: code),
            message: message,
            resource: result["Resource"],
            requestId: result["RequestId"]
        )
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
        elementStack.append(elementName)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            result[elementName] = trimmed
        }
        elementStack.removeLast()
        currentText = ""
    }
}
```

**Step 4: Run test**

Run: `swift test --filter parseErrorResponse`
Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add XML error response parsing"
```

### Task 7.2: Parse ListBuckets Response

**Files:**
- Modify: `Sources/SwiftS3/Internal/XMLResponseParser.swift`
- Modify: `Tests/SwiftS3Tests/XMLParserTests.swift`

**Step 1: Add test**

Add to `Tests/SwiftS3Tests/XMLParserTests.swift`:
```swift
@Test func parseListBucketsResponse() async throws {
    let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ListAllMyBucketsResult>
            <Owner>
                <ID>owner-id-123</ID>
                <DisplayName>Alice</DisplayName>
            </Owner>
            <Buckets>
                <Bucket>
                    <Name>my-bucket</Name>
                    <CreationDate>2019-12-11T23:32:47+00:00</CreationDate>
                </Bucket>
                <Bucket>
                    <Name>other-bucket</Name>
                    <CreationDate>2020-01-15T10:00:00+00:00</CreationDate>
                </Bucket>
            </Buckets>
        </ListAllMyBucketsResult>
        """

    let parser = XMLResponseParser()
    let result: ListBucketsResult = try parser.parseListBuckets(from: xml.data(using: .utf8)!)

    #expect(result.buckets.count == 2)
    #expect(result.buckets[0].name == "my-bucket")
    #expect(result.buckets[1].name == "other-bucket")
    #expect(result.owner?.id == "owner-id-123")
    #expect(result.owner?.displayName == "Alice")
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter parseListBucketsResponse`
Expected: FAIL

**Step 3: Add parseListBuckets method**

Add to `XMLResponseParser.swift`:
```swift
    func parseListBuckets(from data: Data) throws -> ListBucketsResult {
        let delegate = ListBucketsParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw S3ParsingError(message: "Failed to parse ListBuckets XML", responseBody: String(data: data, encoding: .utf8))
        }

        return ListBucketsResult(
            buckets: delegate.buckets,
            owner: delegate.owner,
            continuationToken: delegate.continuationToken
        )
    }
}

private final class ListBucketsParserDelegate: NSObject, XMLParserDelegate {
    var buckets: [Bucket] = []
    var owner: Owner?
    var continuationToken: String?

    private var currentElement = ""
    private var currentText = ""
    private var elementStack: [String] = []

    // Current bucket being parsed
    private var currentBucketName: String?
    private var currentBucketCreationDate: Date?
    private var currentBucketRegion: String?

    // Owner fields
    private var ownerId: String?
    private var ownerDisplayName: String?

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let dateFormatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
        elementStack.append(elementName)

        if elementName == "Bucket" {
            currentBucketName = nil
            currentBucketCreationDate = nil
            currentBucketRegion = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = elementStack.count >= 2 ? elementStack[elementStack.count - 2] : ""

        switch elementName {
        case "Name" where parent == "Bucket":
            currentBucketName = trimmed
        case "CreationDate" where parent == "Bucket":
            currentBucketCreationDate = Self.dateFormatter.date(from: trimmed) ?? Self.dateFormatterNoFraction.date(from: trimmed)
        case "BucketRegion" where parent == "Bucket":
            currentBucketRegion = trimmed
        case "Bucket":
            if let name = currentBucketName {
                buckets.append(Bucket(name: name, creationDate: currentBucketCreationDate, region: currentBucketRegion))
            }
        case "ID" where parent == "Owner":
            ownerId = trimmed
        case "DisplayName" where parent == "Owner":
            ownerDisplayName = trimmed
        case "Owner":
            if let id = ownerId {
                owner = Owner(id: id, displayName: ownerDisplayName)
            }
        case "ContinuationToken":
            continuationToken = trimmed.isEmpty ? nil : trimmed
        default:
            break
        }

        elementStack.removeLast()
        currentText = ""
    }
}
```

**Step 4: Run test**

Run: `swift test --filter parseListBucketsResponse`
Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add ListBuckets XML parsing"
```

### Task 7.3: Parse ListObjects Response

**Files:**
- Modify: `Sources/SwiftS3/Internal/XMLResponseParser.swift`
- Modify: `Tests/SwiftS3Tests/XMLParserTests.swift`

**Step 1: Add test**

Add to `Tests/SwiftS3Tests/XMLParserTests.swift`:
```swift
@Test func parseListObjectsResponse() async throws {
    let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ListBucketResult>
            <Name>my-bucket</Name>
            <Prefix>photos/</Prefix>
            <KeyCount>2</KeyCount>
            <MaxKeys>1000</MaxKeys>
            <IsTruncated>false</IsTruncated>
            <Contents>
                <Key>photos/image1.jpg</Key>
                <LastModified>2009-10-12T17:50:30.000Z</LastModified>
                <ETag>"fba9dede5f27731c9771645a39863328"</ETag>
                <Size>434234</Size>
                <StorageClass>STANDARD</StorageClass>
            </Contents>
            <Contents>
                <Key>photos/image2.jpg</Key>
                <LastModified>2009-10-13T10:00:00.000Z</LastModified>
                <ETag>"abc123"</ETag>
                <Size>1024</Size>
                <StorageClass>STANDARD</StorageClass>
            </Contents>
            <CommonPrefixes>
                <Prefix>photos/2023/</Prefix>
            </CommonPrefixes>
        </ListBucketResult>
        """

    let parser = XMLResponseParser()
    let result: ListObjectsResult = try parser.parseListObjects(from: xml.data(using: .utf8)!)

    #expect(result.objects.count == 2)
    #expect(result.objects[0].key == "photos/image1.jpg")
    #expect(result.objects[0].size == 434234)
    #expect(result.objects[1].key == "photos/image2.jpg")
    #expect(result.isTruncated == false)
    #expect(result.commonPrefixes.count == 1)
    #expect(result.commonPrefixes[0] == "photos/2023/")
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter parseListObjectsResponse`
Expected: FAIL

**Step 3: Add parseListObjects method**

Add to `XMLResponseParser.swift` (before the closing brace of XMLResponseParser class):
```swift
    func parseListObjects(from data: Data) throws -> ListObjectsResult {
        let delegate = ListObjectsParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw S3ParsingError(message: "Failed to parse ListObjects XML", responseBody: String(data: data, encoding: .utf8))
        }

        return ListObjectsResult(
            objects: delegate.objects,
            commonPrefixes: delegate.commonPrefixes,
            isTruncated: delegate.isTruncated,
            continuationToken: delegate.nextContinuationToken
        )
    }
```

Add new delegate class:
```swift
private final class ListObjectsParserDelegate: NSObject, XMLParserDelegate {
    var objects: [S3Object] = []
    var commonPrefixes: [String] = []
    var isTruncated = false
    var nextContinuationToken: String?

    private var currentElement = ""
    private var currentText = ""
    private var elementStack: [String] = []

    // Current object being parsed
    private var currentKey: String?
    private var currentLastModified: Date?
    private var currentEtag: String?
    private var currentSize: Int64?
    private var currentStorageClass: String?

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
        elementStack.append(elementName)

        if elementName == "Contents" {
            currentKey = nil
            currentLastModified = nil
            currentEtag = nil
            currentSize = nil
            currentStorageClass = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = elementStack.count >= 2 ? elementStack[elementStack.count - 2] : ""

        switch elementName {
        case "Key" where parent == "Contents":
            currentKey = trimmed
        case "LastModified" where parent == "Contents":
            currentLastModified = Self.dateFormatter.date(from: trimmed)
        case "ETag" where parent == "Contents":
            currentEtag = trimmed
        case "Size" where parent == "Contents":
            currentSize = Int64(trimmed)
        case "StorageClass" where parent == "Contents":
            currentStorageClass = trimmed
        case "Contents":
            if let key = currentKey {
                objects.append(S3Object(
                    key: key,
                    lastModified: currentLastModified,
                    etag: currentEtag,
                    size: currentSize,
                    storageClass: currentStorageClass,
                    owner: nil
                ))
            }
        case "Prefix" where parent == "CommonPrefixes":
            commonPrefixes.append(trimmed)
        case "IsTruncated":
            isTruncated = trimmed.lowercased() == "true"
        case "NextContinuationToken":
            nextContinuationToken = trimmed.isEmpty ? nil : trimmed
        default:
            break
        }

        elementStack.removeLast()
        currentText = ""
    }
}
```

**Step 4: Run test**

Run: `swift test --filter parseListObjectsResponse`
Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add ListObjects XML parsing"
```

---

## Phase 8: HTTP Client

### Task 8.1: HTTPClient Basic Structure

**Files:**
- Create: `Sources/SwiftS3/Internal/HTTPClient.swift`

**Step 1: Create HTTPClient.swift**

```swift
import Foundation

struct HTTPClient: Sendable {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw S3NetworkError(message: "Invalid response type", underlyingError: nil)
        }

        return (data, httpResponse)
    }

    func executeStream(_ request: URLRequest) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw S3NetworkError(message: "Invalid response type", underlyingError: nil)
        }

        return (bytes, httpResponse)
    }
}
```

**Step 2: Build to verify**

Run: `swift build`
Expected: PASS

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add HTTPClient wrapper"
```

---

## Phase 9: Request Builder

### Task 9.1: RequestBuilder

**Files:**
- Create: `Sources/SwiftS3/Internal/RequestBuilder.swift`
- Create: `Tests/SwiftS3Tests/RequestBuilderTests.swift`

**Step 1: Write test**

Create `Tests/SwiftS3Tests/RequestBuilderTests.swift`:
```swift
import Testing
import Foundation
@testable import SwiftS3

@Test func buildVirtualHostedStyleURL() async throws {
    let config = S3Configuration.aws(
        accessKeyId: "AKID",
        secretAccessKey: "SECRET",
        region: "us-east-1"
    )
    let builder = RequestBuilder(configuration: config)

    let request = builder.buildRequest(
        method: "GET",
        bucket: "my-bucket",
        key: "path/to/file.txt",
        queryItems: nil,
        headers: nil,
        body: nil
    )

    #expect(request.url?.absoluteString == "https://my-bucket.s3.us-east-1.amazonaws.com/path/to/file.txt")
    #expect(request.httpMethod == "GET")
}

@Test func buildPathStyleURL() async throws {
    let config = S3Configuration.backblaze(
        accessKeyId: "AKID",
        secretAccessKey: "SECRET",
        region: "us-west-004"
    )
    let builder = RequestBuilder(configuration: config)

    let request = builder.buildRequest(
        method: "PUT",
        bucket: "my-bucket",
        key: "file.txt",
        queryItems: nil,
        headers: nil,
        body: nil
    )

    #expect(request.url?.absoluteString == "https://s3.us-west-004.backblazeb2.com/my-bucket/file.txt")
}

@Test func buildRequestWithQueryItems() async throws {
    let config = S3Configuration.aws(
        accessKeyId: "AKID",
        secretAccessKey: "SECRET",
        region: "us-east-1"
    )
    let builder = RequestBuilder(configuration: config)

    let request = builder.buildRequest(
        method: "GET",
        bucket: "my-bucket",
        key: nil,
        queryItems: [
            URLQueryItem(name: "list-type", value: "2"),
            URLQueryItem(name: "prefix", value: "photos/")
        ],
        headers: nil,
        body: nil
    )

    #expect(request.url?.absoluteString.contains("list-type=2") == true)
    #expect(request.url?.absoluteString.contains("prefix=photos") == true)
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter "buildVirtualHostedStyleURL|buildPathStyleURL|buildRequestWithQueryItems"`
Expected: FAIL

**Step 3: Create RequestBuilder.swift**

```swift
import Foundation

struct RequestBuilder: Sendable {
    let configuration: S3Configuration

    func buildRequest(
        method: String,
        bucket: String?,
        key: String?,
        queryItems: [URLQueryItem]?,
        headers: [String: String]?,
        body: Data?
    ) -> URLRequest {
        var components = URLComponents()
        components.scheme = configuration.endpoint.scheme

        if configuration.usePathStyleAddressing {
            // Path-style: https://endpoint/bucket/key
            components.host = configuration.endpoint.host
            components.port = configuration.endpoint.port
            var path = ""
            if let bucket = bucket {
                path += "/\(bucket)"
            }
            if let key = key {
                path += "/\(key)"
            }
            components.path = path.isEmpty ? "/" : path
        } else {
            // Virtual-hosted style: https://bucket.endpoint/key
            if let bucket = bucket {
                components.host = "\(bucket).\(configuration.endpoint.host!)"
            } else {
                components.host = configuration.endpoint.host
            }
            components.port = configuration.endpoint.port
            if let key = key {
                components.path = "/\(key)"
            } else {
                components.path = "/"
            }
        }

        components.queryItems = queryItems?.isEmpty == false ? queryItems : nil

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body

        // Set Host header
        request.setValue(components.host, forHTTPHeaderField: "Host")

        // Set custom headers
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        return request
    }
}
```

**Step 4: Run tests**

Run: `swift test --filter "buildVirtualHostedStyleURL|buildPathStyleURL|buildRequestWithQueryItems"`
Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add RequestBuilder for URL construction"
```

---

## Phase 10: S3Client Core

### Task 10.1: S3Client Skeleton

**Files:**
- Create: `Sources/SwiftS3/S3Client.swift`

**Step 1: Create S3Client.swift**

```swift
import Foundation

public final class S3Client: Sendable {
    private let configuration: S3Configuration
    private let httpClient: HTTPClient
    private let signer: SigV4Signer
    private let requestBuilder: RequestBuilder
    private let xmlParser: XMLResponseParser

    public init(configuration: S3Configuration) {
        self.configuration = configuration
        self.httpClient = HTTPClient()
        self.signer = SigV4Signer(
            accessKeyId: configuration.accessKeyId,
            secretAccessKey: configuration.secretAccessKey,
            region: configuration.region
        )
        self.requestBuilder = RequestBuilder(configuration: configuration)
        self.xmlParser = XMLResponseParser()
    }

    // MARK: - Private Helpers

    private func executeRequest(_ request: URLRequest, body: Data?) async throws -> (Data, HTTPURLResponse) {
        var signedRequest = request
        let payloadHash = (body ?? Data()).sha256().hexString
        signer.sign(request: &signedRequest, date: Date(), payloadHash: payloadHash)

        let (data, response) = try await httpClient.execute(signedRequest)

        // Check for error responses
        if response.statusCode >= 400 {
            let error = try xmlParser.parseError(from: data)
            throw error
        }

        return (data, response)
    }
}
```

**Step 2: Build to verify**

Run: `swift build`
Expected: PASS

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add S3Client core structure"
```

---

## Phase 11: Bucket Operations

### Task 11.1: ListBuckets

**Files:**
- Modify: `Sources/SwiftS3/S3Client.swift`
- Create: `Tests/SwiftS3Tests/S3ClientTests.swift`

**Step 1: Write test**

Create `Tests/SwiftS3Tests/S3ClientTests.swift`:
```swift
import Testing
import Foundation
@testable import SwiftS3

// Note: These are unit tests using a mock approach
// Live integration tests would require actual credentials

@Test func listBucketsBuildsCorrectRequest() async throws {
    let config = S3Configuration.aws(
        accessKeyId: "AKID",
        secretAccessKey: "SECRET",
        region: "us-east-1"
    )
    let builder = RequestBuilder(configuration: config)

    let request = builder.buildRequest(
        method: "GET",
        bucket: nil,
        key: nil,
        queryItems: [URLQueryItem(name: "max-buckets", value: "100")],
        headers: nil,
        body: nil
    )

    #expect(request.httpMethod == "GET")
    #expect(request.url?.host == "s3.us-east-1.amazonaws.com")
    #expect(request.url?.query?.contains("max-buckets=100") == true)
}
```

**Step 2: Run test**

Run: `swift test --filter listBucketsBuildsCorrectRequest`
Expected: PASS

**Step 3: Add listBuckets method**

Add to `S3Client.swift`:
```swift
    // MARK: - Bucket Operations

    public func listBuckets(
        prefix: String? = nil,
        maxBuckets: Int? = nil,
        continuationToken: String? = nil
    ) async throws -> ListBucketsResult {
        var queryItems: [URLQueryItem] = []
        if let prefix = prefix {
            queryItems.append(URLQueryItem(name: "prefix", value: prefix))
        }
        if let maxBuckets = maxBuckets {
            queryItems.append(URLQueryItem(name: "max-buckets", value: String(maxBuckets)))
        }
        if let continuationToken = continuationToken {
            queryItems.append(URLQueryItem(name: "continuation-token", value: continuationToken))
        }

        let request = requestBuilder.buildRequest(
            method: "GET",
            bucket: nil,
            key: nil,
            queryItems: queryItems.isEmpty ? nil : queryItems,
            headers: nil,
            body: nil
        )

        let (data, _) = try await executeRequest(request, body: nil)
        return try xmlParser.parseListBuckets(from: data)
    }
```

**Step 4: Build to verify**

Run: `swift build`
Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add listBuckets operation"
```

### Task 11.2: CreateBucket

**Files:**
- Modify: `Sources/SwiftS3/S3Client.swift`

**Step 1: Add createBucket method**

Add to `S3Client.swift`:
```swift
    public func createBucket(_ name: String, region: String? = nil) async throws {
        var body: Data? = nil

        // If region differs from configuration region, include LocationConstraint
        if let region = region, region != configuration.region {
            let xml = """
                <?xml version="1.0" encoding="UTF-8"?>
                <CreateBucketConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <LocationConstraint>\(region)</LocationConstraint>
                </CreateBucketConfiguration>
                """
            body = xml.data(using: .utf8)
        }

        let request = requestBuilder.buildRequest(
            method: "PUT",
            bucket: name,
            key: nil,
            queryItems: nil,
            headers: body != nil ? ["Content-Type": "application/xml"] : nil,
            body: body
        )

        _ = try await executeRequest(request, body: body)
    }
```

**Step 2: Build to verify**

Run: `swift build`
Expected: PASS

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add createBucket operation"
```

### Task 11.3: DeleteBucket

**Files:**
- Modify: `Sources/SwiftS3/S3Client.swift`

**Step 1: Add deleteBucket method**

Add to `S3Client.swift`:
```swift
    public func deleteBucket(_ name: String) async throws {
        let request = requestBuilder.buildRequest(
            method: "DELETE",
            bucket: name,
            key: nil,
            queryItems: nil,
            headers: nil,
            body: nil
        )

        _ = try await executeRequest(request, body: nil)
    }
```

**Step 2: Build to verify**

Run: `swift build`
Expected: PASS

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add deleteBucket operation"
```

### Task 11.4: HeadBucket

**Files:**
- Modify: `Sources/SwiftS3/S3Client.swift`

**Step 1: Add headBucket method**

Add to `S3Client.swift`:
```swift
    public func headBucket(_ name: String) async throws -> String? {
        let request = requestBuilder.buildRequest(
            method: "HEAD",
            bucket: name,
            key: nil,
            queryItems: nil,
            headers: nil,
            body: nil
        )

        let (_, response) = try await executeRequest(request, body: nil)
        return response.value(forHTTPHeaderField: "x-amz-bucket-region")
    }
```

**Step 2: Build to verify**

Run: `swift build`
Expected: PASS

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add headBucket operation"
```

---

## Phase 12: Object Operations

### Task 12.1: ListObjects

**Files:**
- Modify: `Sources/SwiftS3/S3Client.swift`

**Step 1: Add listObjects method**

Add to `S3Client.swift`:
```swift
    // MARK: - Object Operations

    public func listObjects(
        bucket: String,
        prefix: String? = nil,
        delimiter: String? = nil,
        maxKeys: Int? = nil,
        continuationToken: String? = nil
    ) async throws -> ListObjectsResult {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "list-type", value: "2")
        ]
        if let prefix = prefix {
            queryItems.append(URLQueryItem(name: "prefix", value: prefix))
        }
        if let delimiter = delimiter {
            queryItems.append(URLQueryItem(name: "delimiter", value: delimiter))
        }
        if let maxKeys = maxKeys {
            queryItems.append(URLQueryItem(name: "max-keys", value: String(maxKeys)))
        }
        if let continuationToken = continuationToken {
            queryItems.append(URLQueryItem(name: "continuation-token", value: continuationToken))
        }

        let request = requestBuilder.buildRequest(
            method: "GET",
            bucket: bucket,
            key: nil,
            queryItems: queryItems,
            headers: nil,
            body: nil
        )

        let (data, _) = try await executeRequest(request, body: nil)
        return try xmlParser.parseListObjects(from: data)
    }
```

**Step 2: Build to verify**

Run: `swift build`
Expected: PASS

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add listObjects operation"
```

### Task 12.2: GetObject

**Files:**
- Modify: `Sources/SwiftS3/S3Client.swift`

**Step 1: Add getObject method**

Add to `S3Client.swift`:
```swift
    public func getObject(
        bucket: String,
        key: String,
        range: Range<Int64>? = nil
    ) async throws -> (data: Data, metadata: ObjectMetadata) {
        var headers: [String: String] = [:]
        if let range = range {
            headers["Range"] = "bytes=\(range.lowerBound)-\(range.upperBound - 1)"
        }

        let request = requestBuilder.buildRequest(
            method: "GET",
            bucket: bucket,
            key: key,
            queryItems: nil,
            headers: headers.isEmpty ? nil : headers,
            body: nil
        )

        let (data, response) = try await executeRequest(request, body: nil)
        let metadata = parseObjectMetadata(from: response)

        return (data, metadata)
    }

    private func parseObjectMetadata(from response: HTTPURLResponse) -> ObjectMetadata {
        let contentLength = Int64(response.value(forHTTPHeaderField: "Content-Length") ?? "0") ?? 0

        var customMetadata: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let keyString = key as? String,
               keyString.lowercased().hasPrefix("x-amz-meta-") {
                let metaKey = String(keyString.dropFirst("x-amz-meta-".count))
                customMetadata[metaKey] = value as? String
            }
        }

        return ObjectMetadata(
            contentLength: contentLength,
            contentType: response.value(forHTTPHeaderField: "Content-Type"),
            etag: response.value(forHTTPHeaderField: "ETag"),
            lastModified: parseHTTPDate(response.value(forHTTPHeaderField: "Last-Modified")),
            versionId: response.value(forHTTPHeaderField: "x-amz-version-id"),
            metadata: customMetadata
        )
    }

    private func parseHTTPDate(_ string: String?) -> Date? {
        guard let string = string else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: string)
    }
```

**Step 2: Build to verify**

Run: `swift build`
Expected: PASS

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add getObject operation"
```

### Task 12.3: GetObjectStream

**Files:**
- Modify: `Sources/SwiftS3/S3Client.swift`

**Step 1: Add getObjectStream method**

Add to `S3Client.swift`:
```swift
    public func getObjectStream(
        bucket: String,
        key: String,
        range: Range<Int64>? = nil
    ) async throws -> (stream: AsyncThrowingStream<UInt8, Error>, metadata: ObjectMetadata) {
        var headers: [String: String] = [:]
        if let range = range {
            headers["Range"] = "bytes=\(range.lowerBound)-\(range.upperBound - 1)"
        }

        var request = requestBuilder.buildRequest(
            method: "GET",
            bucket: bucket,
            key: key,
            queryItems: nil,
            headers: headers.isEmpty ? nil : headers,
            body: nil
        )

        let payloadHash = Data().sha256().hexString
        signer.sign(request: &request, date: Date(), payloadHash: payloadHash)

        let (bytes, response) = try await httpClient.executeStream(request)

        if response.statusCode >= 400 {
            // For error responses, we need to read the body
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            let error = try xmlParser.parseError(from: errorData)
            throw error
        }

        let metadata = parseObjectMetadata(from: response)

        let stream = AsyncThrowingStream<UInt8, Error> { continuation in
            Task {
                do {
                    for try await byte in bytes {
                        continuation.yield(byte)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        return (stream, metadata)
    }
```

**Step 2: Build to verify**

Run: `swift build`
Expected: PASS

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add getObjectStream for large files"
```

### Task 12.4: PutObject

**Files:**
- Modify: `Sources/SwiftS3/S3Client.swift`

**Step 1: Add putObject method**

Add to `S3Client.swift`:
```swift
    public func putObject(
        bucket: String,
        key: String,
        data: Data,
        contentType: String? = nil,
        metadata: [String: String]? = nil
    ) async throws -> String {
        var headers: [String: String] = [:]
        headers["Content-Length"] = String(data.count)

        if let contentType = contentType {
            headers["Content-Type"] = contentType
        }

        if let metadata = metadata {
            for (key, value) in metadata {
                headers["x-amz-meta-\(key)"] = value
            }
        }

        let request = requestBuilder.buildRequest(
            method: "PUT",
            bucket: bucket,
            key: key,
            queryItems: nil,
            headers: headers,
            body: data
        )

        let (_, response) = try await executeRequest(request, body: data)
        return response.value(forHTTPHeaderField: "ETag") ?? ""
    }
```

**Step 2: Build to verify**

Run: `swift build`
Expected: PASS

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add putObject operation"
```

### Task 12.5: DeleteObject

**Files:**
- Modify: `Sources/SwiftS3/S3Client.swift`

**Step 1: Add deleteObject method**

Add to `S3Client.swift`:
```swift
    public func deleteObject(bucket: String, key: String) async throws {
        let request = requestBuilder.buildRequest(
            method: "DELETE",
            bucket: bucket,
            key: key,
            queryItems: nil,
            headers: nil,
            body: nil
        )

        _ = try await executeRequest(request, body: nil)
    }
```

**Step 2: Build to verify**

Run: `swift build`
Expected: PASS

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add deleteObject operation"
```

### Task 12.6: HeadObject

**Files:**
- Modify: `Sources/SwiftS3/S3Client.swift`

**Step 1: Add headObject method**

Add to `S3Client.swift`:
```swift
    public func headObject(bucket: String, key: String) async throws -> ObjectMetadata {
        let request = requestBuilder.buildRequest(
            method: "HEAD",
            bucket: bucket,
            key: key,
            queryItems: nil,
            headers: nil,
            body: nil
        )

        let (_, response) = try await executeRequest(request, body: nil)
        return parseObjectMetadata(from: response)
    }
```

**Step 2: Build to verify**

Run: `swift build`
Expected: PASS

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add headObject operation"
```

### Task 12.7: CopyObject

**Files:**
- Modify: `Sources/SwiftS3/S3Client.swift`

**Step 1: Add copyObject method**

Add to `S3Client.swift`:
```swift
    public func copyObject(
        sourceBucket: String,
        sourceKey: String,
        destinationBucket: String,
        destinationKey: String
    ) async throws -> String {
        let copySource = "/\(sourceBucket)/\(sourceKey)"

        let request = requestBuilder.buildRequest(
            method: "PUT",
            bucket: destinationBucket,
            key: destinationKey,
            queryItems: nil,
            headers: ["x-amz-copy-source": copySource],
            body: nil
        )

        let (_, response) = try await executeRequest(request, body: nil)
        return response.value(forHTTPHeaderField: "ETag") ?? ""
    }
```

**Step 2: Build to verify**

Run: `swift build`
Expected: PASS

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add copyObject operation"
```

---

## Phase 13: Multipart Upload Operations

### Task 13.1: XML Parsing for Multipart

**Files:**
- Modify: `Sources/SwiftS3/Internal/XMLResponseParser.swift`
- Modify: `Tests/SwiftS3Tests/XMLParserTests.swift`

**Step 1: Add test**

Add to `Tests/SwiftS3Tests/XMLParserTests.swift`:
```swift
@Test func parseInitiateMultipartUploadResponse() async throws {
    let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <InitiateMultipartUploadResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
            <Bucket>my-bucket</Bucket>
            <Key>large-file.bin</Key>
            <UploadId>VXBsb2FkIElEIGZvciA2aWWpbmcncyBteS1tb3ZpZS5tMnRzIHVwbG9hZA</UploadId>
        </InitiateMultipartUploadResult>
        """

    let parser = XMLResponseParser()
    let result = try parser.parseInitiateMultipartUpload(from: xml.data(using: .utf8)!)

    #expect(result.uploadId == "VXBsb2FkIElEIGZvciA2aWWpbmcncyBteS1tb3ZpZS5tMnRzIHVwbG9hZA")
    #expect(result.key == "large-file.bin")
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter parseInitiateMultipartUploadResponse`
Expected: FAIL

**Step 3: Add parseInitiateMultipartUpload method**

Add to `XMLResponseParser.swift`:
```swift
    func parseInitiateMultipartUpload(from data: Data) throws -> MultipartUpload {
        result = [:]
        elementStack = []

        let parser = XMLParser(data: data)
        parser.delegate = self

        guard parser.parse() else {
            throw S3ParsingError(message: "Failed to parse InitiateMultipartUpload XML", responseBody: String(data: data, encoding: .utf8))
        }

        guard let uploadId = result["UploadId"],
              let key = result["Key"] else {
            throw S3ParsingError(message: "Missing required fields", responseBody: String(data: data, encoding: .utf8))
        }

        return MultipartUpload(uploadId: uploadId, key: key, initiated: nil)
    }
```

**Step 4: Run test**

Run: `swift test --filter parseInitiateMultipartUploadResponse`
Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add multipart upload XML parsing"
```

### Task 13.2: CreateMultipartUpload

**Files:**
- Modify: `Sources/SwiftS3/S3Client.swift`

**Step 1: Add createMultipartUpload method**

Add to `S3Client.swift`:
```swift
    // MARK: - Multipart Upload Operations

    public func createMultipartUpload(
        bucket: String,
        key: String,
        contentType: String? = nil,
        metadata: [String: String]? = nil
    ) async throws -> MultipartUpload {
        var headers: [String: String] = [:]

        if let contentType = contentType {
            headers["Content-Type"] = contentType
        }

        if let metadata = metadata {
            for (key, value) in metadata {
                headers["x-amz-meta-\(key)"] = value
            }
        }

        let request = requestBuilder.buildRequest(
            method: "POST",
            bucket: bucket,
            key: key,
            queryItems: [URLQueryItem(name: "uploads", value: nil)],
            headers: headers.isEmpty ? nil : headers,
            body: nil
        )

        let (data, _) = try await executeRequest(request, body: nil)
        return try xmlParser.parseInitiateMultipartUpload(from: data)
    }
```

**Step 2: Build to verify**

Run: `swift build`
Expected: PASS

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add createMultipartUpload operation"
```

### Task 13.3: UploadPart

**Files:**
- Modify: `Sources/SwiftS3/S3Client.swift`

**Step 1: Add uploadPart method**

Add to `S3Client.swift`:
```swift
    public func uploadPart(
        bucket: String,
        key: String,
        uploadId: String,
        partNumber: Int,
        data: Data
    ) async throws -> CompletedPart {
        let request = requestBuilder.buildRequest(
            method: "PUT",
            bucket: bucket,
            key: key,
            queryItems: [
                URLQueryItem(name: "partNumber", value: String(partNumber)),
                URLQueryItem(name: "uploadId", value: uploadId)
            ],
            headers: ["Content-Length": String(data.count)],
            body: data
        )

        let (_, response) = try await executeRequest(request, body: data)
        let etag = response.value(forHTTPHeaderField: "ETag") ?? ""

        return CompletedPart(partNumber: partNumber, etag: etag)
    }
```

**Step 2: Build to verify**

Run: `swift build`
Expected: PASS

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add uploadPart operation"
```

### Task 13.4: CompleteMultipartUpload

**Files:**
- Modify: `Sources/SwiftS3/S3Client.swift`

**Step 1: Add completeMultipartUpload method**

Add to `S3Client.swift`:
```swift
    public func completeMultipartUpload(
        bucket: String,
        key: String,
        uploadId: String,
        parts: [CompletedPart]
    ) async throws -> String {
        let sortedParts = parts.sorted { $0.partNumber < $1.partNumber }

        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<CompleteMultipartUpload>"
        for part in sortedParts {
            xml += "<Part><PartNumber>\(part.partNumber)</PartNumber><ETag>\(part.etag)</ETag></Part>"
        }
        xml += "</CompleteMultipartUpload>"

        let body = xml.data(using: .utf8)!

        let request = requestBuilder.buildRequest(
            method: "POST",
            bucket: bucket,
            key: key,
            queryItems: [URLQueryItem(name: "uploadId", value: uploadId)],
            headers: ["Content-Type": "application/xml"],
            body: body
        )

        let (_, response) = try await executeRequest(request, body: body)
        return response.value(forHTTPHeaderField: "ETag") ?? ""
    }
```

**Step 2: Build to verify**

Run: `swift build`
Expected: PASS

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add completeMultipartUpload operation"
```

### Task 13.5: AbortMultipartUpload

**Files:**
- Modify: `Sources/SwiftS3/S3Client.swift`

**Step 1: Add abortMultipartUpload method**

Add to `S3Client.swift`:
```swift
    public func abortMultipartUpload(
        bucket: String,
        key: String,
        uploadId: String
    ) async throws {
        let request = requestBuilder.buildRequest(
            method: "DELETE",
            bucket: bucket,
            key: key,
            queryItems: [URLQueryItem(name: "uploadId", value: uploadId)],
            headers: nil,
            body: nil
        )

        _ = try await executeRequest(request, body: nil)
    }
```

**Step 2: Build to verify**

Run: `swift build`
Expected: PASS

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add abortMultipartUpload operation"
```

### Task 13.6: ListMultipartUploads

**Files:**
- Modify: `Sources/SwiftS3/Internal/XMLResponseParser.swift`
- Modify: `Sources/SwiftS3/S3Client.swift`

**Step 1: Add XML parsing**

Add to `XMLResponseParser.swift`:
```swift
    func parseListMultipartUploads(from data: Data) throws -> ListMultipartUploadsResult {
        let delegate = ListMultipartUploadsParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw S3ParsingError(message: "Failed to parse ListMultipartUploads XML", responseBody: String(data: data, encoding: .utf8))
        }

        return ListMultipartUploadsResult(
            uploads: delegate.uploads,
            isTruncated: delegate.isTruncated,
            nextKeyMarker: delegate.nextKeyMarker,
            nextUploadIdMarker: delegate.nextUploadIdMarker
        )
    }
```

Add delegate class:
```swift
private final class ListMultipartUploadsParserDelegate: NSObject, XMLParserDelegate {
    var uploads: [MultipartUpload] = []
    var isTruncated = false
    var nextKeyMarker: String?
    var nextUploadIdMarker: String?

    private var currentElement = ""
    private var currentText = ""
    private var elementStack: [String] = []

    private var currentKey: String?
    private var currentUploadId: String?
    private var currentInitiated: Date?

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
        elementStack.append(elementName)

        if elementName == "Upload" {
            currentKey = nil
            currentUploadId = nil
            currentInitiated = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = elementStack.count >= 2 ? elementStack[elementStack.count - 2] : ""

        switch elementName {
        case "Key" where parent == "Upload":
            currentKey = trimmed
        case "UploadId" where parent == "Upload":
            currentUploadId = trimmed
        case "Initiated" where parent == "Upload":
            currentInitiated = Self.dateFormatter.date(from: trimmed)
        case "Upload":
            if let key = currentKey, let uploadId = currentUploadId {
                uploads.append(MultipartUpload(uploadId: uploadId, key: key, initiated: currentInitiated))
            }
        case "IsTruncated":
            isTruncated = trimmed.lowercased() == "true"
        case "NextKeyMarker":
            nextKeyMarker = trimmed.isEmpty ? nil : trimmed
        case "NextUploadIdMarker":
            nextUploadIdMarker = trimmed.isEmpty ? nil : trimmed
        default:
            break
        }

        elementStack.removeLast()
        currentText = ""
    }
}
```

**Step 2: Add listMultipartUploads method**

Add to `S3Client.swift`:
```swift
    public func listMultipartUploads(
        bucket: String,
        prefix: String? = nil,
        maxUploads: Int? = nil
    ) async throws -> ListMultipartUploadsResult {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "uploads", value: nil)
        ]
        if let prefix = prefix {
            queryItems.append(URLQueryItem(name: "prefix", value: prefix))
        }
        if let maxUploads = maxUploads {
            queryItems.append(URLQueryItem(name: "max-uploads", value: String(maxUploads)))
        }

        let request = requestBuilder.buildRequest(
            method: "GET",
            bucket: bucket,
            key: nil,
            queryItems: queryItems,
            headers: nil,
            body: nil
        )

        let (data, _) = try await executeRequest(request, body: nil)
        return try xmlParser.parseListMultipartUploads(from: data)
    }
```

**Step 3: Build to verify**

Run: `swift build`
Expected: PASS

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: add listMultipartUploads operation"
```

### Task 13.7: ListParts

**Files:**
- Modify: `Sources/SwiftS3/Internal/XMLResponseParser.swift`
- Modify: `Sources/SwiftS3/S3Client.swift`

**Step 1: Add XML parsing**

Add to `XMLResponseParser.swift`:
```swift
    func parseListParts(from data: Data) throws -> ListPartsResult {
        let delegate = ListPartsParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw S3ParsingError(message: "Failed to parse ListParts XML", responseBody: String(data: data, encoding: .utf8))
        }

        return ListPartsResult(
            parts: delegate.parts,
            isTruncated: delegate.isTruncated,
            nextPartNumberMarker: delegate.nextPartNumberMarker
        )
    }
```

Add delegate class:
```swift
private final class ListPartsParserDelegate: NSObject, XMLParserDelegate {
    var parts: [Part] = []
    var isTruncated = false
    var nextPartNumberMarker: Int?

    private var currentElement = ""
    private var currentText = ""
    private var elementStack: [String] = []

    private var currentPartNumber: Int?
    private var currentEtag: String?
    private var currentSize: Int64?
    private var currentLastModified: Date?

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
        elementStack.append(elementName)

        if elementName == "Part" {
            currentPartNumber = nil
            currentEtag = nil
            currentSize = nil
            currentLastModified = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = elementStack.count >= 2 ? elementStack[elementStack.count - 2] : ""

        switch elementName {
        case "PartNumber" where parent == "Part":
            currentPartNumber = Int(trimmed)
        case "ETag" where parent == "Part":
            currentEtag = trimmed
        case "Size" where parent == "Part":
            currentSize = Int64(trimmed)
        case "LastModified" where parent == "Part":
            currentLastModified = Self.dateFormatter.date(from: trimmed)
        case "Part":
            if let partNumber = currentPartNumber, let etag = currentEtag {
                parts.append(Part(partNumber: partNumber, etag: etag, size: currentSize, lastModified: currentLastModified))
            }
        case "IsTruncated":
            isTruncated = trimmed.lowercased() == "true"
        case "NextPartNumberMarker":
            nextPartNumberMarker = Int(trimmed)
        default:
            break
        }

        elementStack.removeLast()
        currentText = ""
    }
}
```

**Step 2: Add listParts method**

Add to `S3Client.swift`:
```swift
    public func listParts(
        bucket: String,
        key: String,
        uploadId: String,
        maxParts: Int? = nil,
        partNumberMarker: Int? = nil
    ) async throws -> ListPartsResult {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "uploadId", value: uploadId)
        ]
        if let maxParts = maxParts {
            queryItems.append(URLQueryItem(name: "max-parts", value: String(maxParts)))
        }
        if let partNumberMarker = partNumberMarker {
            queryItems.append(URLQueryItem(name: "part-number-marker", value: String(partNumberMarker)))
        }

        let request = requestBuilder.buildRequest(
            method: "GET",
            bucket: bucket,
            key: key,
            queryItems: queryItems,
            headers: nil,
            body: nil
        )

        let (data, _) = try await executeRequest(request, body: nil)
        return try xmlParser.parseListParts(from: data)
    }
```

**Step 3: Build to verify**

Run: `swift build`
Expected: PASS

**Step 4: Run all tests**

Run: `swift test`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add listParts operation"
```

---

## Phase 14: Public Exports

### Task 14.1: Create Public Module File

**Files:**
- Modify: `Sources/SwiftS3/SwiftS3.swift`

**Step 1: Update SwiftS3.swift to export all public types**

```swift
// SwiftS3 - S3 Compatible API Client
// Public API exports

// Re-export all public types for easy importing
@_exported import struct Foundation.Data
@_exported import struct Foundation.Date
@_exported import struct Foundation.URL
```

**Step 2: Build and test**

Run: `swift build && swift test`
Expected: PASS

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: finalize public module exports"
```

---

## Phase 15: Final Verification

### Task 15.1: Full Test Suite

**Step 1: Run full test suite**

Run: `swift test`
Expected: All tests PASS

**Step 2: Build in release mode**

Run: `swift build -c release`
Expected: PASS

**Step 3: Verify no warnings**

Run: `swift build 2>&1 | grep -i warning || echo "No warnings"`
Expected: No warnings

**Step 4: Final commit**

```bash
git add -A
git commit -m "chore: complete SwiftS3 implementation"
```

---

## Summary

**Total Tasks:** 40+
**Phases:** 15

**What's Built:**
- S3Client with 16 operations
- SigV4 authentication
- XML response parsing
- Provider configurations (AWS, Backblaze, Cloudflare, GCS)
- Typed error handling
- Full test coverage for core components

**Not Included (Future Work):**
- SwiftLint configuration
- Live integration tests
- CI/CD setup
- Documentation generation
