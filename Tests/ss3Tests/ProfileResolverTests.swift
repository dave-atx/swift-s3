import Testing
import Foundation
@testable import ss3

@Test func profileResolverLooksUpFromConfig() throws {
    let config = ConfigFile(profiles: ["e2": "https://s3.example.com"])
    let resolver = ProfileResolver(config: config)

    let profile = try resolver.resolve(profileName: "e2", cliOverride: nil)

    #expect(profile.name == "e2")
    #expect(profile.endpoint.absoluteString == "https://s3.example.com")
}

@Test func profileResolverCLIOverrideWins() throws {
    let config = ConfigFile(profiles: ["e2": "https://config.example.com"])
    let resolver = ProfileResolver(config: config)

    let profile = try resolver.resolve(
        profileName: "e2",
        cliOverride: (name: "e2", url: "https://cli.example.com")
    )

    #expect(profile.endpoint.absoluteString == "https://cli.example.com")
}

@Test func profileResolverThrowsForUnknownProfile() throws {
    let config = ConfigFile(profiles: ["e2": "https://s3.example.com"])
    let resolver = ProfileResolver(config: config)

    #expect(throws: ProfileResolverError.self) {
        try resolver.resolve(profileName: "unknown", cliOverride: nil)
    }
}

@Test func profileResolverErrorShowsAvailableProfiles() throws {
    let config = ConfigFile(profiles: [
        "b2": "https://b2.example.com",
        "e2": "https://e2.example.com",
        "r2": "https://r2.example.com"
    ])
    let resolver = ProfileResolver(config: config)

    do {
        _ = try resolver.resolve(profileName: "unknown", cliOverride: nil)
        Issue.record("Expected error to be thrown")
    } catch let error as ProfileResolverError {
        let description = error.description
        #expect(description.contains("unknown"))
        #expect(description.contains("b2"))
        #expect(description.contains("e2"))
        #expect(description.contains("r2"))
    }
}

@Test func profileResolverWithNilConfigRequiresCLIOverride() throws {
    let resolver = ProfileResolver(config: nil)

    // Should fail without CLI override
    #expect(throws: ProfileResolverError.self) {
        try resolver.resolve(profileName: "e2", cliOverride: nil)
    }

    // Should succeed with CLI override
    let profile = try resolver.resolve(
        profileName: "e2",
        cliOverride: (name: "e2", url: "https://s3.example.com")
    )
    #expect(profile.name == "e2")
}
