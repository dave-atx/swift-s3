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
}
