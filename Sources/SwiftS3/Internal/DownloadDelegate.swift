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
            // Try to extract resume data (use string key for cross-platform compatibility)
            let resumeData = (error as NSError).userInfo["NSURLSessionDownloadTaskResumeData"] as? Data
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
