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
