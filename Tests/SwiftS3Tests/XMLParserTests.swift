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
