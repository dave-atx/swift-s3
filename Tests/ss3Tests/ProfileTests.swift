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
