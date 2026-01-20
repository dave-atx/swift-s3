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
