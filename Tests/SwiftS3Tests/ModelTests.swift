import Testing
@testable import SwiftS3

@Test func ownerEquality() async throws {
    let owner1 = Owner(id: "123", displayName: "Alice")
    let owner2 = Owner(id: "123", displayName: "Alice")
    let owner3 = Owner(id: "456", displayName: "Bob")

    #expect(owner1 == owner2)
    #expect(owner1 != owner3)
}
