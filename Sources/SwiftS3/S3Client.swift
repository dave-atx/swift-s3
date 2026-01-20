import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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
}
