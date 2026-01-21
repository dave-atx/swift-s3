import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol HTTPClientProtocol: Sendable {
    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
    func download(
        _ request: URLRequest,
        to destination: URL,
        resumeData: Data?,
        progress: (@Sendable (Int64, Int64?) -> Void)?
    ) async throws -> (URL, HTTPURLResponse)
}

struct HTTPClient: HTTPClientProtocol, Sendable {
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

    // TODO: Find cross-platform solution for streaming HTTP responses on Linux.
    // URLSession.AsyncBytes is not available in FoundationNetworking.
    // See: https://github.com/dave-atx/swift-s3/issues/3
    #if !canImport(FoundationNetworking)
    func executeStream(_ request: URLRequest) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw S3NetworkError(message: "Invalid response type", underlyingError: nil)
        }

        return (bytes, httpResponse)
    }
    #endif

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
}
