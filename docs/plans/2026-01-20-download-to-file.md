# Download Object to File Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add cross-platform `downloadObject()` method that streams S3 objects directly to disk with progress reporting and resume support.

**Architecture:** Uses `URLSessionDownloadTask` (available on macOS and Linux) wrapped in a delegate that bridges callbacks to async/await. Progress reported via closure, resume via `Data` token.

**Tech Stack:** Foundation, FoundationNetworking (Linux), URLSessionDownloadDelegate, CheckedContinuation

---

## Task 1: Add S3DownloadError Type

**Files:**
- Create: `Sources/SwiftS3/Errors/S3DownloadError.swift`
- Test: `Tests/SwiftS3Tests/ErrorTests.swift`

**Step 1: Write the failing test**

Add to `Tests/SwiftS3Tests/ErrorTests.swift`:

```swift
@Test func s3DownloadErrorIncludesResumeData() {
    let resumeData = Data([0x01, 0x02, 0x03])
    let error = S3DownloadError(
        message: "Download interrupted",
        resumeData: resumeData,
        underlyingError: nil
    )

    #expect(error.message == "Download interrupted")
    #expect(error.resumeData == resumeData)
    #expect(error.underlyingError == nil)
}

@Test func s3DownloadErrorWithoutResumeData() {
    let underlying = NSError(domain: "test", code: 1)
    let error = S3DownloadError(
        message: "Network failed",
        resumeData: nil,
        underlyingError: underlying
    )

    #expect(error.message == "Network failed")
    #expect(error.resumeData == nil)
    #expect(error.underlyingError as? NSError === underlying)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter SwiftS3Tests.ErrorTests/testS3DownloadErrorIncludesResumeData`
Expected: FAIL - cannot find type 'S3DownloadError'

**Step 3: Write minimal implementation**

Create `Sources/SwiftS3/Errors/S3DownloadError.swift`:

```swift
import Foundation

public struct S3DownloadError: S3Error, Sendable {
    public let message: String
    public let resumeData: Data?
    public let underlyingError: (any Error)?

    public init(message: String, resumeData: Data?, underlyingError: (any Error)?) {
        self.message = message
        self.resumeData = resumeData
        self.underlyingError = underlyingError
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter SwiftS3Tests.ErrorTests`
Expected: All ErrorTests PASS

**Step 5: Commit**

```bash
git add Sources/SwiftS3/Errors/S3DownloadError.swift Tests/SwiftS3Tests/ErrorTests.swift
git commit -m "feat: add S3DownloadError with resume data support"
```

---

## Task 2: Create DownloadDelegate

**Files:**
- Create: `Sources/SwiftS3/Internal/DownloadDelegate.swift`
- Test: `Tests/SwiftS3Tests/DownloadDelegateTests.swift`

**Step 1: Write the failing test**

Create `Tests/SwiftS3Tests/DownloadDelegateTests.swift`:

```swift
import Foundation
import Testing
@testable import SwiftS3

@Test func downloadDelegateReportsProgress() async throws {
    var progressUpdates: [(Int64, Int64?)] = []

    let delegate = DownloadDelegate(
        destination: URL(fileURLWithPath: "/tmp/test-download"),
        progressHandler: { written, total in
            progressUpdates.append((written, total))
        }
    )

    // Simulate progress callback
    let session = URLSession.shared
    let task = session.downloadTask(with: URL(string: "https://example.com")!)

    delegate.urlSession(
        session,
        downloadTask: task,
        didWriteData: 1024,
        totalBytesWritten: 1024,
        totalBytesExpectedToWrite: 4096
    )

    #expect(progressUpdates.count == 1)
    #expect(progressUpdates[0].0 == 1024)
    #expect(progressUpdates[0].1 == 4096)
}

@Test func downloadDelegateHandlesUnknownTotal() async throws {
    var progressUpdates: [(Int64, Int64?)] = []

    let delegate = DownloadDelegate(
        destination: URL(fileURLWithPath: "/tmp/test-download"),
        progressHandler: { written, total in
            progressUpdates.append((written, total))
        }
    )

    let session = URLSession.shared
    let task = session.downloadTask(with: URL(string: "https://example.com")!)

    // NSURLSessionTransferSizeUnknown = -1
    delegate.urlSession(
        session,
        downloadTask: task,
        didWriteData: 1024,
        totalBytesWritten: 1024,
        totalBytesExpectedToWrite: -1
    )

    #expect(progressUpdates.count == 1)
    #expect(progressUpdates[0].0 == 1024)
    #expect(progressUpdates[0].1 == nil)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter SwiftS3Tests.DownloadDelegateTests`
Expected: FAIL - cannot find type 'DownloadDelegate'

**Step 3: Write minimal implementation**

Create `Sources/SwiftS3/Internal/DownloadDelegate.swift`:

```swift
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progressHandler: (@Sendable (Int64, Int64?) -> Void)?

    private var continuation: CheckedContinuation<(URL, HTTPURLResponse), any Error>?
    private var tempFileURL: URL?
    private var httpResponse: HTTPURLResponse?

    init(
        destination: URL,
        progressHandler: (@Sendable (Int64, Int64?) -> Void)?
    ) {
        self.destination = destination
        self.progressHandler = progressHandler
        super.init()
    }

    func setContinuation(_ continuation: CheckedContinuation<(URL, HTTPURLResponse), any Error>) {
        self.continuation = continuation
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total: Int64? = totalBytesExpectedToWrite == NSURLSessionTransferSizeUnknown ? nil : totalBytesExpectedToWrite
        progressHandler?(totalBytesWritten, total)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Store temp location and response for completion handler
        tempFileURL = location
        if let response = downloadTask.response as? HTTPURLResponse {
            httpResponse = response
        }

        // Copy file immediately (system deletes temp file after this returns)
        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: location, to: destination)
        } catch {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        defer {
            session.invalidateAndCancel()
        }

        if let error = error {
            // Try to extract resume data
            let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
            let downloadError = S3DownloadError(
                message: error.localizedDescription,
                resumeData: resumeData,
                underlyingError: error
            )
            continuation?.resume(throwing: downloadError)
        } else if let response = httpResponse {
            continuation?.resume(returning: (destination, response))
        } else {
            continuation?.resume(throwing: S3NetworkError(
                message: "No response received",
                underlyingError: nil
            ))
        }
        continuation = nil
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter SwiftS3Tests.DownloadDelegateTests`
Expected: All DownloadDelegateTests PASS

**Step 5: Commit**

```bash
git add Sources/SwiftS3/Internal/DownloadDelegate.swift Tests/SwiftS3Tests/DownloadDelegateTests.swift
git commit -m "feat: add DownloadDelegate for URLSessionDownloadTask"
```

---

## Task 3: Add download() Method to HTTPClient

**Files:**
- Modify: `Sources/SwiftS3/Internal/HTTPClient.swift`
- Test: `Tests/SwiftS3Tests/HTTPClientTests.swift`

**Step 1: Write the failing test**

Create `Tests/SwiftS3Tests/HTTPClientTests.swift`:

```swift
import Foundation
import Testing
@testable import SwiftS3

@Test func httpClientDownloadMethodExists() async throws {
    let client = HTTPClient()

    // Just verify the method signature compiles
    // Actual download testing requires network, covered in integration tests
    let _: (
        URLRequest,
        URL,
        Data?,
        (@Sendable (Int64, Int64?) -> Void)?
    ) async throws -> (URL, HTTPURLResponse) = client.download

    #expect(Bool(true)) // Method exists if this compiles
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter SwiftS3Tests.HTTPClientTests`
Expected: FAIL - value of type 'HTTPClient' has no member 'download'

**Step 3: Write minimal implementation**

Add to `Sources/SwiftS3/Internal/HTTPClient.swift` after the existing `execute` method:

```swift
    func download(
        _ request: URLRequest,
        to destination: URL,
        resumeData: Data?,
        progress: (@Sendable (Int64, Int64?) -> Void)?
    ) async throws -> (URL, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadDelegate(
                destination: destination,
                progressHandler: progress
            )
            delegate.setContinuation(continuation)

            let configuration = URLSessionConfiguration.default
            let session = URLSession(
                configuration: configuration,
                delegate: delegate,
                delegateQueue: nil
            )

            let task: URLSessionDownloadTask
            if let resumeData = resumeData {
                task = session.downloadTask(withResumeData: resumeData)
            } else {
                task = session.downloadTask(with: request)
            }

            task.resume()
        }
    }
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter SwiftS3Tests.HTTPClientTests`
Expected: All HTTPClientTests PASS

**Step 5: Commit**

```bash
git add Sources/SwiftS3/Internal/HTTPClient.swift Tests/SwiftS3Tests/HTTPClientTests.swift
git commit -m "feat: add download() method to HTTPClient"
```

---

## Task 4: Add downloadObject() to S3Client

**Files:**
- Modify: `Sources/SwiftS3/S3Client.swift`
- Test: `Tests/SwiftS3Tests/S3ClientTests.swift`

**Step 1: Write the failing test**

Add to `Tests/SwiftS3Tests/S3ClientTests.swift`:

```swift
@Test func downloadObjectBuildsCorrectRequest() async throws {
    var capturedRequest: URLRequest?

    let mockHTTPClient = MockHTTPClient(
        downloadHandler: { request, destination, resumeData, progress in
            capturedRequest = request
            // Create empty file at destination
            FileManager.default.createFile(atPath: destination.path, contents: Data(), attributes: nil)

            // Return mock response
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Length": "1024",
                    "Content-Type": "application/octet-stream",
                    "ETag": "\"abc123\""
                ]
            )!
            return (destination, response)
        }
    )

    let config = S3Configuration(
        accessKeyId: "AKIAIOSFODNN7EXAMPLE",
        secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region: "us-east-1",
        endpoint: URL(string: "https://s3.us-east-1.amazonaws.com")!
    )

    let client = S3Client(configuration: config, httpClient: mockHTTPClient)

    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test-download-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let metadata = try await client.downloadObject(
        bucket: "my-bucket",
        key: "my-key.txt",
        to: tempFile
    )

    #expect(capturedRequest != nil)
    #expect(capturedRequest?.httpMethod == "GET")
    #expect(capturedRequest?.url?.host?.contains("my-bucket") == true || capturedRequest?.url?.path.contains("my-bucket") == true)
    #expect(capturedRequest?.url?.path.contains("my-key.txt") == true)
    #expect(metadata.contentLength == 1024)
    #expect(metadata.contentType == "application/octet-stream")
    #expect(metadata.etag == "\"abc123\"")
}
```

**Step 2: Update MockHTTPClient to support download**

Add to `Tests/SwiftS3Tests/S3ClientTests.swift` (modify existing MockHTTPClient or create if needed):

```swift
struct MockHTTPClient: Sendable {
    let executeHandler: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    let downloadHandler: (@Sendable (URLRequest, URL, Data?, (@Sendable (Int64, Int64?) -> Void)?) async throws -> (URL, HTTPURLResponse))?

    init(
        executeHandler: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse) = { _ in
            fatalError("executeHandler not set")
        },
        downloadHandler: (@Sendable (URLRequest, URL, Data?, (@Sendable (Int64, Int64?) -> Void)?) async throws -> (URL, HTTPURLResponse))? = nil
    ) {
        self.executeHandler = executeHandler
        self.downloadHandler = downloadHandler
    }

    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await executeHandler(request)
    }

    func download(
        _ request: URLRequest,
        to destination: URL,
        resumeData: Data?,
        progress: (@Sendable (Int64, Int64?) -> Void)?
    ) async throws -> (URL, HTTPURLResponse) {
        guard let handler = downloadHandler else {
            fatalError("downloadHandler not set")
        }
        return try await handler(request, destination, resumeData, progress)
    }
}
```

**Step 3: Run test to verify it fails**

Run: `swift test --filter SwiftS3Tests.S3ClientTests/testDownloadObjectBuildsCorrectRequest`
Expected: FAIL - S3Client has no member 'downloadObject'

**Step 4: Refactor S3Client to accept HTTPClient protocol**

First, create protocol in `Sources/SwiftS3/Internal/HTTPClient.swift`:

```swift
protocol HTTPClientProtocol: Sendable {
    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
    func download(
        _ request: URLRequest,
        to destination: URL,
        resumeData: Data?,
        progress: (@Sendable (Int64, Int64?) -> Void)?
    ) async throws -> (URL, HTTPURLResponse)
}

extension HTTPClient: HTTPClientProtocol {}
```

Then update `S3Client` init to accept the protocol:

```swift
public final class S3Client: Sendable {
    private let configuration: S3Configuration
    private let httpClient: any HTTPClientProtocol
    // ... rest unchanged

    public init(configuration: S3Configuration) {
        self.configuration = configuration
        self.httpClient = HTTPClient()
        // ... rest unchanged
    }

    // Internal init for testing
    init(configuration: S3Configuration, httpClient: any HTTPClientProtocol) {
        self.configuration = configuration
        self.httpClient = httpClient
        self.signer = SigV4Signer(
            accessKeyId: configuration.accessKeyId,
            secretAccessKey: configuration.secretAccessKey,
            region: configuration.region
        )
        self.requestBuilder = RequestBuilder(configuration: configuration)
        self.xmlParser = XMLResponseParser()
    }
}
```

**Step 5: Write downloadObject implementation**

Add to `Sources/SwiftS3/S3Client.swift` after `headObject`:

```swift
    public func downloadObject(
        bucket: String,
        key: String,
        to destination: URL,
        progress: (@Sendable (Int64, Int64?) -> Void)? = nil,
        resumeData: Data? = nil
    ) async throws -> ObjectMetadata {
        // If resuming, use resume data directly (contains original request)
        if let resumeData = resumeData {
            let (_, response) = try await httpClient.download(
                URLRequest(url: URL(string: "https://placeholder")!), // ignored when resuming
                to: destination,
                resumeData: resumeData,
                progress: progress
            )

            if response.statusCode >= 400 {
                throw S3APIError(code: .unknown, message: "Download failed with status \(response.statusCode)")
            }

            return parseObjectMetadata(from: response)
        }

        // Fresh download: build and sign request
        var request = requestBuilder.buildRequest(
            method: "GET",
            bucket: bucket,
            key: key,
            queryItems: nil,
            headers: nil,
            body: nil
        )

        let payloadHash = Data().sha256().hexString
        signer.sign(request: &request, date: Date(), payloadHash: payloadHash)

        let (_, response) = try await httpClient.download(
            request,
            to: destination,
            resumeData: nil,
            progress: progress
        )

        if response.statusCode >= 400 {
            throw S3APIError(code: .unknown, message: "Download failed with status \(response.statusCode)")
        }

        return parseObjectMetadata(from: response)
    }
```

**Step 6: Run tests to verify they pass**

Run: `swift test --filter SwiftS3Tests.S3ClientTests`
Expected: All S3ClientTests PASS

**Step 7: Run all tests**

Run: `swift test`
Expected: All tests PASS

**Step 8: Commit**

```bash
git add Sources/SwiftS3/Internal/HTTPClient.swift Sources/SwiftS3/S3Client.swift Tests/SwiftS3Tests/S3ClientTests.swift
git commit -m "feat: add downloadObject() to S3Client with progress and resume"
```

---

## Task 5: Add Progress Callback Test

**Files:**
- Modify: `Tests/SwiftS3Tests/S3ClientTests.swift`

**Step 1: Write the test**

Add to `Tests/SwiftS3Tests/S3ClientTests.swift`:

```swift
@Test func downloadObjectReportsProgress() async throws {
    var progressUpdates: [(Int64, Int64?)] = []

    let mockHTTPClient = MockHTTPClient(
        downloadHandler: { request, destination, resumeData, progress in
            // Simulate progress updates
            progress?(1024, 4096)
            progress?(2048, 4096)
            progress?(4096, 4096)

            FileManager.default.createFile(atPath: destination.path, contents: Data(repeating: 0, count: 4096), attributes: nil)

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Length": "4096"]
            )!
            return (destination, response)
        }
    )

    let config = S3Configuration(
        accessKeyId: "AKIAIOSFODNN7EXAMPLE",
        secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region: "us-east-1",
        endpoint: URL(string: "https://s3.us-east-1.amazonaws.com")!
    )

    let client = S3Client(configuration: config, httpClient: mockHTTPClient)

    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test-progress-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempFile) }

    _ = try await client.downloadObject(
        bucket: "my-bucket",
        key: "my-key.txt",
        to: tempFile,
        progress: { written, total in
            progressUpdates.append((written, total))
        }
    )

    #expect(progressUpdates.count == 3)
    #expect(progressUpdates[0] == (1024, 4096))
    #expect(progressUpdates[1] == (2048, 4096))
    #expect(progressUpdates[2] == (4096, 4096))
}
```

**Step 2: Run test**

Run: `swift test --filter SwiftS3Tests.S3ClientTests/testDownloadObjectReportsProgress`
Expected: PASS

**Step 3: Commit**

```bash
git add Tests/SwiftS3Tests/S3ClientTests.swift
git commit -m "test: add progress callback test for downloadObject"
```

---

## Task 6: Final Verification and Cleanup

**Step 1: Run all tests**

Run: `swift test`
Expected: All tests PASS

**Step 2: Build for both platforms**

Run: `swift build`
Expected: Build succeeds

**Step 3: Update design doc status**

Edit `docs/plans/2026-01-20-download-to-file-design.md`, change:
```
**Status:** Proposed
```
to:
```
**Status:** Implemented
```

**Step 4: Final commit**

```bash
git add docs/plans/2026-01-20-download-to-file-design.md
git commit -m "docs: mark download-to-file design as implemented"
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | S3DownloadError type | 1 new, 1 modified |
| 2 | DownloadDelegate | 1 new, 1 new test |
| 3 | HTTPClient.download() | 1 modified, 1 new test |
| 4 | S3Client.downloadObject() | 2 modified, 1 test file |
| 5 | Progress callback test | 1 modified |
| 6 | Final verification | 1 modified |

**Total commits:** 6
