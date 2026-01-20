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

@Test func parseListObjectsResponse() async throws {
    let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ListBucketResult>
            <Name>my-bucket</Name>
            <Prefix>photos/</Prefix>
            <KeyCount>2</KeyCount>
            <MaxKeys>1000</MaxKeys>
            <IsTruncated>false</IsTruncated>
            <Contents>
                <Key>photos/image1.jpg</Key>
                <LastModified>2009-10-12T17:50:30.000Z</LastModified>
                <ETag>"fba9dede5f27731c9771645a39863328"</ETag>
                <Size>434234</Size>
                <StorageClass>STANDARD</StorageClass>
            </Contents>
            <Contents>
                <Key>photos/image2.jpg</Key>
                <LastModified>2009-10-12T17:50:31.000Z</LastModified>
                <ETag>"fba9dede5f27731c9771645a39863329"</ETag>
                <Size>123456</Size>
                <StorageClass>STANDARD</StorageClass>
            </Contents>
        </ListBucketResult>
        """

    let parser = XMLResponseParser()
    let result: ListObjectsResult = try parser.parseListObjects(from: xml.data(using: .utf8)!)

    #expect(result.objects.count == 2)
    #expect(result.objects[0].key == "photos/image1.jpg")
    #expect(result.objects[0].size == 434234)
    #expect(result.objects[0].etag == "\"fba9dede5f27731c9771645a39863328\"")
    #expect(result.objects[1].key == "photos/image2.jpg")
    #expect(result.name == "my-bucket")
    #expect(result.prefix == "photos/")
    #expect(result.isTruncated == false)
}

@Test func parseInitiateMultipartUploadResponse() async throws {
    let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <InitiateMultipartUploadResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
            <Bucket>my-bucket</Bucket>
            <Key>large-file.bin</Key>
            <UploadId>VXBsb2FkIElEIGZvciA2aWWpbmcncyBteS1tb3ZpZS5tMnRzIHVwbG9hZA</UploadId>
        </InitiateMultipartUploadResult>
        """

    let parser = XMLResponseParser()
    let result = try parser.parseInitiateMultipartUpload(from: xml.data(using: .utf8)!)

    #expect(result.uploadId == "VXBsb2FkIElEIGZvciA2aWWpbmcncyBteS1tb3ZpZS5tMnRzIHVwbG9hZA")
    #expect(result.key == "large-file.bin")
}
