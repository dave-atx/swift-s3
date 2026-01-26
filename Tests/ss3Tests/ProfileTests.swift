import Testing
@testable import ss3

@Test func profileParsesSimpleURL() throws {
    let profile = try Profile.parse(name: "e2", url: "https://s3.example.com")
    #expect(profile.name == "e2")
    #expect(profile.endpoint.absoluteString == "https://s3.example.com")
    #expect(profile.region == "auto")
    #expect(profile.bucket == nil)
    #expect(profile.accessKeyId == nil)
    #expect(profile.secretAccessKey == nil)
}

@Test func profileParsesCredentialsFromURL() throws {
    let profile = try Profile.parse(name: "e2", url: "https://keyid:secret@s3.example.com")
    #expect(profile.accessKeyId == "keyid")
    #expect(profile.secretAccessKey == "secret")
    #expect(profile.endpoint.absoluteString == "https://s3.example.com")
}

@Test func profileParsesBucketFromVirtualHost() throws {
    let profile = try Profile.parse(name: "e2", url: "https://mybucket.s3.us-west-2.example.com")
    #expect(profile.bucket == "mybucket")
    #expect(profile.region == "us-west-2")
}

@Test func profileParsesRegionAfterS3Marker() throws {
    let profile = try Profile.parse(name: "e2", url: "https://s3.eu-central-1.amazonaws.com")
    #expect(profile.bucket == nil)
    #expect(profile.region == "eu-central-1")
}

@Test func profileParsesFullURL() throws {
    let profile = try Profile.parse(name: "b2", url: "https://key:secret@mybucket.s3.sjc-003.backblazeb2.com")
    #expect(profile.name == "b2")
    #expect(profile.accessKeyId == "key")
    #expect(profile.secretAccessKey == "secret")
    #expect(profile.bucket == "mybucket")
    #expect(profile.region == "sjc-003")
    #expect(profile.endpoint.absoluteString == "https://mybucket.s3.sjc-003.backblazeb2.com")
}

@Test func profileThrowsForInvalidURL() throws {
    #expect(throws: ProfileError.self) {
        try Profile.parse(name: "e2", url: "not a url")
    }
}

@Test func profileResolvesWithURLCredentials() throws {
    let profile = try Profile.parse(name: "e2", url: "https://key:secret@s3.example.com")
    let env = Environment(getenv: { _ in nil })
    let resolved = try profile.resolve(with: env)

    #expect(resolved.accessKeyId == "key")
    #expect(resolved.secretAccessKey == "secret")
}

@Test func profileResolvesWithEnvCredentials() throws {
    let profile = try Profile.parse(name: "e2", url: "https://s3.example.com")
    let env = Environment(getenv: { key in
        switch key {
        case "SS3_E2_ACCESS_KEY": return "env-key"
        case "SS3_E2_SECRET_KEY": return "env-secret"
        default: return nil
        }
    })
    let resolved = try profile.resolve(with: env)

    #expect(resolved.accessKeyId == "env-key")
    #expect(resolved.secretAccessKey == "env-secret")
}

@Test func profileEnvCredentialsOverrideURL() throws {
    let profile = try Profile.parse(name: "e2", url: "https://url-key:url-secret@s3.example.com")
    let env = Environment(getenv: { key in
        switch key {
        case "SS3_E2_ACCESS_KEY": return "env-key"
        case "SS3_E2_SECRET_KEY": return "env-secret"
        default: return nil
        }
    })
    let resolved = try profile.resolve(with: env)

    // Env vars should override URL credentials
    #expect(resolved.accessKeyId == "env-key")
    #expect(resolved.secretAccessKey == "env-secret")
}

@Test func profileURLCredentialsUsedWhenNoEnvVars() throws {
    let profile = try Profile.parse(name: "e2", url: "https://url-key:url-secret@s3.example.com")
    let env = Environment(getenv: { _ in nil })  // No env vars
    let resolved = try profile.resolve(with: env)

    #expect(resolved.accessKeyId == "url-key")
    #expect(resolved.secretAccessKey == "url-secret")
}

@Test func profileThrowsWhenNoCredentials() throws {
    let profile = try Profile.parse(name: "e2", url: "https://s3.example.com")
    let env = Environment(getenv: { _ in nil })

    #expect(throws: ProfileError.self) {
        try profile.resolve(with: env)
    }
}

@Test func profileEnvVarNormalizesName() {
    #expect(Profile.envVarPrefix(for: "prod-backup") == "SS3_PROD_BACKUP")
    #expect(Profile.envVarPrefix(for: "my.profile") == "SS3_MY_PROFILE")
    #expect(Profile.envVarPrefix(for: "e2") == "SS3_E2")
}
