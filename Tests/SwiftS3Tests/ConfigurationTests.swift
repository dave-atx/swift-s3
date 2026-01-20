import Testing
import Foundation
@testable import SwiftS3

@Test func configurationStoresProperties() async throws {
    let config = S3Configuration(
        accessKeyId: "AKIAIOSFODNN7EXAMPLE",
        secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region: "us-east-1",
        endpoint: URL(string: "https://s3.us-east-1.amazonaws.com")!,
        usePathStyleAddressing: false
    )

    #expect(config.accessKeyId == "AKIAIOSFODNN7EXAMPLE")
    #expect(config.region == "us-east-1")
    #expect(config.usePathStyleAddressing == false)
}

@Test func awsConfigurationEndpoint() async throws {
    let config = S3Configuration.aws(
        accessKeyId: "AKIA...",
        secretAccessKey: "secret",
        region: "us-west-2"
    )

    #expect(config.endpoint.absoluteString == "https://s3.us-west-2.amazonaws.com")
    #expect(config.region == "us-west-2")
    #expect(config.usePathStyleAddressing == false)
}

@Test func backblazeConfigurationEndpoint() async throws {
    let config = S3Configuration.backblaze(
        accessKeyId: "keyId",
        secretAccessKey: "appKey",
        region: "us-west-004"
    )

    #expect(config.endpoint.absoluteString == "https://s3.us-west-004.backblazeb2.com")
    #expect(config.usePathStyleAddressing == true)
}

@Test func cloudflareConfigurationEndpoint() async throws {
    let config = S3Configuration.cloudflare(
        accessKeyId: "accessKey",
        secretAccessKey: "secretKey",
        accountId: "abc123def456"
    )

    #expect(config.endpoint.absoluteString == "https://abc123def456.r2.cloudflarestorage.com")
    #expect(config.usePathStyleAddressing == true)
}

@Test func gcsConfigurationEndpoint() async throws {
    let config = S3Configuration.gcs(
        accessKeyId: "GOOG...",
        secretAccessKey: "secret"
    )

    #expect(config.endpoint.absoluteString == "https://storage.googleapis.com")
    #expect(config.usePathStyleAddressing == true)
}
