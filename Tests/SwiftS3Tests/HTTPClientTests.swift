import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import SwiftS3

@Test func httpClientDownloadMethodExists() async throws {
    let client = HTTPClient()

    // Just verify the method signature compiles
    // Actual download testing requires network, covered in integration tests
    let _: (
        URLRequest,
        URL,
        Data?,
        (@Sendable (Int64, Int64?) -> Void)?
    ) async throws -> (URL, HTTPURLResponse) = client.download

    #expect(Bool(true)) // Method exists if this compiles
}
