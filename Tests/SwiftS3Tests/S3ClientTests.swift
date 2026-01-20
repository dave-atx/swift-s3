import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import SwiftS3

// Note: These are unit tests using a mock approach
// Live integration tests would require actual credentials

struct MockHTTPClient: HTTPClientProtocol {
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

final class RequestCapture: @unchecked Sendable {
    var request: URLRequest?
}

@Test func downloadObjectBuildsCorrectRequest() async throws {
    let capture = RequestCapture()

    let mockHTTPClient = MockHTTPClient(
        downloadHandler: { request, destination, resumeData, progress in
            capture.request = request
            _ = FileManager.default.createFile(atPath: destination.path, contents: Data(), attributes: nil)

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

    #expect(capture.request != nil)
    #expect(capture.request?.httpMethod == "GET")
    #expect(capture.request?.url?.host?.contains("my-bucket") == true || capture.request?.url?.path.contains("my-bucket") == true)
    #expect(capture.request?.url?.path.contains("my-key.txt") == true)
    #expect(metadata.contentLength == 1024)
    #expect(metadata.contentType == "application/octet-stream")
    #expect(metadata.etag == "\"abc123\"")
}
