import Foundation
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

@Test func s3APIErrorCodeMapping() async throws {
    let error = S3APIError(
        code: .noSuchBucket,
        message: "Bucket not found",
        resource: "/my-bucket",
        requestId: "abc123"
    )
    #expect(error.code == .noSuchBucket)
    #expect(error.code.rawValue == "NoSuchBucket")
}

@Test func s3APIErrorUnknownCode() async throws {
    let error = S3APIError(
        code: .unknown("CustomError"),
        message: "Something custom",
        resource: nil,
        requestId: nil
    )
    if case .unknown(let code) = error.code {
        #expect(code == "CustomError")
    } else {
        Issue.record("Expected unknown code")
    }
}

@Test func s3DownloadErrorIncludesResumeData() {
    let resumeData = Data([0x01, 0x02, 0x03])
    let error = S3DownloadError(
        message: "Download interrupted",
        resumeData: resumeData,
        underlyingError: nil
    )

    #expect(error.message == "Download interrupted")
    #expect(error.resumeData == resumeData)
    #expect(error.underlyingError == nil)
}

@Test func s3DownloadErrorWithoutResumeData() {
    let underlying = NSError(domain: "test", code: 1)
    let error = S3DownloadError(
        message: "Network failed",
        resumeData: nil,
        underlyingError: underlying
    )

    #expect(error.message == "Network failed")
    #expect(error.resumeData == nil)
    #expect(error.underlyingError as? NSError === underlying)
}
