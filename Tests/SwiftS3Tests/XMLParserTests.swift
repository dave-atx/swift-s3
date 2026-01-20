import Testing
import Foundation
@testable import SwiftS3

@Test func parseErrorResponse() async throws {
    let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Error>
            <Code>NoSuchBucket</Code>
            <Message>The specified bucket does not exist</Message>
            <Resource>/mybucket</Resource>
            <RequestId>4442587FB7D0A2F9</RequestId>
        </Error>
        """

    let parser = XMLResponseParser()
    let error: S3APIError = try parser.parseError(from: xml.data(using: .utf8)!)

    #expect(error.code == .noSuchBucket)
    #expect(error.message == "The specified bucket does not exist")
    #expect(error.resource == "/mybucket")
    #expect(error.requestId == "4442587FB7D0A2F9")
}

@Test func parseListBucketsResponse() async throws {
    let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ListAllMyBucketsResult>
            <Owner>
                <ID>owner-id-123</ID>
                <DisplayName>Alice</DisplayName>
            </Owner>
            <Buckets>
                <Bucket>
                    <Name>my-bucket</Name>
                    <CreationDate>2019-12-11T23:32:47+00:00</CreationDate>
                </Bucket>
                <Bucket>
                    <Name>other-bucket</Name>
                    <CreationDate>2020-01-15T10:00:00+00:00</CreationDate>
                </Bucket>
            </Buckets>
        </ListAllMyBucketsResult>
        """

    let parser = XMLResponseParser()
    let result: ListBucketsResult = try parser.parseListBuckets(from: xml.data(using: .utf8)!)

    #expect(result.buckets.count == 2)
    #expect(result.buckets[0].name == "my-bucket")
    #expect(result.buckets[1].name == "other-bucket")
    #expect(result.owner?.id == "owner-id-123")
    #expect(result.owner?.displayName == "Alice")
}
