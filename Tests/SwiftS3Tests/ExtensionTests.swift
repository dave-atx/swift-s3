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

@Test func sha256Hash() async throws {
    let data = Data("hello".utf8)
    let hash = data.sha256()
    // Known SHA256 of "hello"
    #expect(hash.hexString == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
}

@Test func hmacSHA256() async throws {
    let key = Data("key".utf8)
    let message = Data("message".utf8)
    let hmac = message.hmacSHA256(key: key)
    // Known HMAC-SHA256 of "message" with key "key"
    #expect(hmac.hexString == "6e9ef29b75fffc5b7abae527d58fdadb2fe42e7219011976917343065f58ed4a")
}
