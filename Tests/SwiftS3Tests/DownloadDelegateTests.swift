import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import SwiftS3

/// Thread-safe wrapper for collecting progress updates in tests
private final class ProgressCollector: @unchecked Sendable {
    private var updates: [(Int64, Int64?)] = []
    private let lock = NSLock()

    func append(_ written: Int64, _ total: Int64?) {
        lock.lock()
        defer { lock.unlock() }
        updates.append((written, total))
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return updates.count
    }

    subscript(index: Int) -> (Int64, Int64?) {
        lock.lock()
        defer { lock.unlock() }
        return updates[index]
    }
}

@Test func downloadDelegateReportsProgress() async throws {
    let progressUpdates = ProgressCollector()

    let delegate = DownloadDelegate(
        destination: URL(fileURLWithPath: "/tmp/test-download"),
        progressHandler: { written, total in
            progressUpdates.append(written, total)
        }
    )

    // Simulate progress callback
    let session = URLSession.shared
    let exampleURL = try #require(URL(string: "https://example.com"))
    let task = session.downloadTask(with: exampleURL)

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
    let progressUpdates = ProgressCollector()

    let delegate = DownloadDelegate(
        destination: URL(fileURLWithPath: "/tmp/test-download"),
        progressHandler: { written, total in
            progressUpdates.append(written, total)
        }
    )

    let session = URLSession.shared
    let exampleURL = try #require(URL(string: "https://example.com"))
    let task = session.downloadTask(with: exampleURL)

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
