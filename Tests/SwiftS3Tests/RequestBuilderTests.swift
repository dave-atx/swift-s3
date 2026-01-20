import Testing
import Foundation
@testable import SwiftS3

@Test func buildVirtualHostedStyleURL() async throws {
    let config = S3Configuration.aws(
        accessKeyId: "AKID",
        secretAccessKey: "SECRET",
        region: "us-east-1"
    )
    let builder = RequestBuilder(configuration: config)

    let request = builder.buildRequest(
        method: "GET",
        bucket: "my-bucket",
        key: "path/to/file.txt",
        queryItems: nil,
        headers: nil,
        body: nil
    )

    #expect(request.url?.absoluteString == "https://my-bucket.s3.us-east-1.amazonaws.com/path/to/file.txt")
    #expect(request.httpMethod == "GET")
}

@Test func buildPathStyleURL() async throws {
    let config = S3Configuration.backblaze(
        accessKeyId: "AKID",
        secretAccessKey: "SECRET",
        region: "us-west-004"
    )
    let builder = RequestBuilder(configuration: config)

    let request = builder.buildRequest(
        method: "PUT",
        bucket: "my-bucket",
        key: "file.txt",
        queryItems: nil,
        headers: nil,
        body: nil
    )

    #expect(request.url?.absoluteString == "https://s3.us-west-004.backblazeb2.com/my-bucket/file.txt")
}

@Test func buildRequestWithQueryItems() async throws {
    let config = S3Configuration.aws(
        accessKeyId: "AKID",
        secretAccessKey: "SECRET",
        region: "us-east-1"
    )
    let builder = RequestBuilder(configuration: config)

    let request = builder.buildRequest(
        method: "GET",
        bucket: "my-bucket",
        key: nil,
        queryItems: [
            URLQueryItem(name: "list-type", value: "2"),
            URLQueryItem(name: "prefix", value: "photos/")
        ],
        headers: nil,
        body: nil
    )

    #expect(request.url?.absoluteString.contains("list-type=2") == true)
    #expect(request.url?.absoluteString.contains("prefix=photos") == true)
}
