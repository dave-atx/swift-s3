import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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
}
