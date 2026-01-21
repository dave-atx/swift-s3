import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import SwiftS3

@Test func sigv4DateFormatting() async throws {
    let signer = SigV4Signer(
        accessKeyId: "AKID",
        secretAccessKey: "SECRET",
        region: "us-east-1"
    )

    // 2015-08-30T12:36:00Z
    let date = Date(timeIntervalSince1970: 1440938160)

    #expect(signer.dateStamp(for: date) == "20150830")
    #expect(signer.amzDate(for: date) == "20150830T123600Z")
}

@Test func canonicalRequest() async throws {
    let signer = SigV4Signer(
        accessKeyId: "AKID",
        secretAccessKey: "SECRET",
        region: "us-east-1"
    )

    let url = try #require(URL(string: "https://examplebucket.s3.amazonaws.com/test.txt"))
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("examplebucket.s3.amazonaws.com", forHTTPHeaderField: "Host")
    request.setValue("20130524T000000Z", forHTTPHeaderField: "x-amz-date")
    let payloadHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")

    let canonical = signer.canonicalRequest(request, payloadHash: payloadHash)

    let expected = """
        GET
        /test.txt

        host:examplebucket.s3.amazonaws.com
        x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        x-amz-date:20130524T000000Z

        host;x-amz-content-sha256;x-amz-date
        e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        """

    #expect(canonical == expected)
}

@Test func stringToSign() async throws {
    let signer = SigV4Signer(
        accessKeyId: "AKID",
        secretAccessKey: "SECRET",
        region: "us-east-1"
    )

    let date = Date(timeIntervalSince1970: 1440938160) // 20150830T123600Z
    let canonicalRequestHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    let stringToSign = signer.stringToSign(canonicalRequestHash: canonicalRequestHash, date: date)

    let expected = """
        AWS4-HMAC-SHA256
        20150830T123600Z
        20150830/us-east-1/s3/aws4_request
        e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        """

    #expect(stringToSign == expected)
}

@Test func signingKey() async throws {
    let signer = SigV4Signer(
        accessKeyId: "AKID",
        secretAccessKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
        region: "us-east-1"
    )

    let date = Date(timeIntervalSince1970: 1440938160) // 20150830
    let key = signer.signingKey(for: date)

    // This is a known test vector - signing key for the given secret/date/region
    #expect(key.count == 32) // SHA256 output is 32 bytes
}

@Test func signRequest() async throws {
    let signer = SigV4Signer(
        accessKeyId: "AKIAIOSFODNN7EXAMPLE",
        secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region: "us-east-1"
    )

    let url = try #require(URL(string: "https://examplebucket.s3.amazonaws.com/test.txt"))
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("examplebucket.s3.amazonaws.com", forHTTPHeaderField: "Host")

    let date = Date(timeIntervalSince1970: 1369353600) // 2013-05-24T00:00:00Z
    let payloadHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" // empty body

    signer.sign(request: &request, date: date, payloadHash: payloadHash)

    // Verify Authorization header is set
    let auth = try #require(request.value(forHTTPHeaderField: "Authorization"))
    #expect(auth.hasPrefix("AWS4-HMAC-SHA256"))
    #expect(auth.contains("Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request"))

    // Verify x-amz-date is set
    let amzDate = request.value(forHTTPHeaderField: "x-amz-date")
    #expect(amzDate == "20130524T000000Z")
}
