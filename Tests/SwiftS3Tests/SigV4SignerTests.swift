import Testing
import Foundation
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
