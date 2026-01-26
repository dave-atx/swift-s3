import Testing
import Foundation
@testable import ss3

@Test func configFileParsesSingleProfile() throws {
    let json = """
    {
      "e2": "https://s3.example.com"
    }
    """
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID()).json")
    try json.write(to: tempFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let config = try ConfigFile.load(from: tempFile.path)

    #expect(config != nil)
    #expect(config?.profileURL(for: "e2") == "https://s3.example.com")
    #expect(config?.profileURL(for: "unknown") == nil)
}
