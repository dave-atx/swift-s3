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

@Test func configFileParsesMultipleProfiles() throws {
    let json = """
    {
      "e2": "https://key:secret@s3.example.com",
      "r2": "https://r2.cloudflare.com",
      "b2": "https://s3.us-west-001.backblaze.com"
    }
    """
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID()).json")
    try json.write(to: tempFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let config = try ConfigFile.load(from: tempFile.path)

    #expect(config?.profileURL(for: "e2") == "https://key:secret@s3.example.com")
    #expect(config?.profileURL(for: "r2") == "https://r2.cloudflare.com")
    #expect(config?.profileURL(for: "b2") == "https://s3.us-west-001.backblaze.com")
    #expect(config?.availableProfiles == ["b2", "e2", "r2"])
}

@Test func configFileReturnsNilForMissingFile() throws {
    let config = try ConfigFile.load(from: "/nonexistent/path/profiles.json")
    #expect(config == nil)
}

@Test func configFileHandlesEmptyFile() throws {
    let json = "{}"
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID()).json")
    try json.write(to: tempFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let config = try ConfigFile.load(from: tempFile.path)

    #expect(config != nil)
    #expect(config?.availableProfiles.isEmpty == true)
}

@Test func configFileThrowsForMalformedJSON() throws {
    let badJson = "{ not valid json }"
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID()).json")
    try badJson.write(to: tempFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    #expect(throws: ConfigFileError.self) {
        try ConfigFile.load(from: tempFile.path)
    }
}

@Test func configFileDefaultPathUsesXDGConfigHome() {
    let env = Environment(getenv: { key in
        if key == "XDG_CONFIG_HOME" { return "/custom/config" }
        return nil
    })
    let path = ConfigFile.defaultPath(env: env)
    #expect(path == "/custom/config/ss3/profiles.json")
}

@Test func configFileDefaultPathFallsBackToHomeConfig() {
    let env = Environment(getenv: { key in
        if key == "HOME" { return "/home/testuser" }
        return nil
    })
    let path = ConfigFile.defaultPath(env: env)
    #expect(path == "/home/testuser/.config/ss3/profiles.json")
}

@Test func configFileDefaultPathReturnsNilWithoutHome() {
    let env = Environment(getenv: { _ in nil })
    let path = ConfigFile.defaultPath(env: env)
    #expect(path == nil)
}
