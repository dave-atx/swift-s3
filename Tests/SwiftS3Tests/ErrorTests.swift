import Testing
@testable import SwiftS3

@Test func s3ErrorHasMessage() async throws {
    let error = S3NetworkError(message: "Connection failed", underlyingError: nil)
    #expect(error.message == "Connection failed")
}

@Test func s3ParsingErrorIncludesResponseBody() async throws {
    let error = S3ParsingError(message: "Invalid XML", responseBody: "<bad>")
    #expect(error.message == "Invalid XML")
    #expect(error.responseBody == "<bad>")
}
