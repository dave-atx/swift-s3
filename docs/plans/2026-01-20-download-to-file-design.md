# Design: Download Object to File

**Issue:** https://github.com/dave-atx/swift-s3/issues/3
**Date:** 2026-01-20
**Status:** Implemented

## Problem

The `getObjectStream` method relies on `URLSession.AsyncBytes`, which is unavailable on Linux. This design proposes an alternate solution: downloading directly to a file using `URLSessionDownloadTask`, which is available on both platforms.

## Goals

- Large file downloads without memory bloat
- Resume support for interrupted downloads
- Progress reporting
- Cross-platform (macOS + Linux)
- Clean async/await API

## Non-Goals

- ETag validation on resume
- Automatic retry logic
- Concurrent chunk downloads

## Public API

```swift
public func downloadObject(
    bucket: String,
    key: String,
    to destination: URL,
    progress: (@Sendable (Int64, Int64?) -> Void)? = nil,
    resumeData: Data? = nil
) async throws -> ObjectMetadata
```

### Parameters

- `destination` - Local file URL where the object will be saved
- `progress` - Optional callback receiving `(bytesWritten, totalBytes)`. Total is nil if Content-Length unknown.
- `resumeData` - Optional data from a previous interrupted download to resume from

### Returns

- `ObjectMetadata` - Same metadata as `getObject` (content type, etag, last modified, etc.)

### Error Handling

On failure, throws `S3DownloadError`:

```swift
public struct S3DownloadError: S3Error, Sendable {
    public let message: String
    public let resumeData: Data?
    public let underlyingError: Error?
}
```

The `resumeData` can be passed to a subsequent `downloadObject` call to resume the download.

## Internal Architecture

### DownloadDelegate

New file: `Sources/SwiftS3/Internal/DownloadDelegate.swift`

Bridges `URLSessionDownloadDelegate` callbacks to async/await using `CheckedContinuation`:

```swift
final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    private let continuation: CheckedContinuation<URL, Error>
    private let progressHandler: (@Sendable (Int64, Int64?) -> Void)?

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL)

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64)

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?)
}
```

### HTTPClient Extension

New method in `Sources/SwiftS3/Internal/HTTPClient.swift`:

```swift
func download(
    _ request: URLRequest,
    to destination: URL,
    resumeData: Data?,
    progress: (@Sendable (Int64, Int64?) -> Void)?
) async throws -> (URL, HTTPURLResponse)
```

- Creates a dedicated `URLSession` with `DownloadDelegate` for each download
- Uses `downloadTask(withResumeData:)` when resuming
- Uses `downloadTask(with:)` for fresh downloads
- Returns temp file URL; caller moves to final destination

### S3Client Integration

The `downloadObject` method in `S3Client`:

1. If `resumeData` provided, skip request building and use resume path
2. Otherwise, build and sign the request normally
3. Call `httpClient.download()`
4. Move temp file to destination
5. Parse and return metadata from response

## Resume Flow

1. User calls `downloadObject(resumeData: nil)` → download starts
2. Network fails mid-download → delegate captures resume data
3. Method throws `S3DownloadError` with `resumeData` populated
4. User stores `resumeData` (disk or memory)
5. User calls `downloadObject(resumeData: savedData)` → download resumes

### Caveats

Resume data is opaque and platform-specific. It may become invalid if:
- Too much time passes (server-side timeout)
- The object changes on S3

These edge cases are not handled; the download will fail and user must retry without resume data.

## Files Changed

| File | Change |
|------|--------|
| `Sources/SwiftS3/S3Client.swift` | Add `downloadObject()` method |
| `Sources/SwiftS3/Internal/HTTPClient.swift` | Add `download()` method |
| `Sources/SwiftS3/Internal/DownloadDelegate.swift` | New file |
| `Sources/SwiftS3/Errors/S3DownloadError.swift` | New file |

## Testing Strategy

- Unit tests: Mock `HTTPClient` to verify request building and metadata parsing
- Integration tests: Require live S3 credentials, test actual downloads with progress and resume
