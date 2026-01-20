import Testing
import Foundation
@testable import SwiftS3

@Test func dataToHexString() async throws {
    let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
    #expect(data.hexString == "deadbeef")
}

@Test func emptyDataToHexString() async throws {
    let data = Data()
    #expect(data.hexString == "")
}
