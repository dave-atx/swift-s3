import Testing
import ArgumentParser
@testable import ss3

@Test func globalOptionsParsesProfile() throws {
    let options = try GlobalOptions.parse(["--profile", "e2", "https://s3.example.com"])

    #expect(options.profileArgs == ["e2", "https://s3.example.com"])
}

@Test func globalOptionsRequiresTwoProfileArgs() throws {
    // Missing URL
    #expect(throws: (any Error).self) {
        let options = try GlobalOptions.parse(["--profile", "e2"])
        _ = try options.parseProfile()
    }
}

@Test func globalOptionsParseProfileReturnsProfile() throws {
    let options = try GlobalOptions.parse(["--profile", "e2", "https://key:secret@s3.example.com"])
    let profile = try options.parseProfile()

    #expect(profile.name == "e2")
    #expect(profile.accessKeyId == "key")
}

@Test func globalOptionsFormatDefault() throws {
    let options = try GlobalOptions.parse(["--profile", "e2", "https://s3.example.com"])
    #expect(options.format == .human)
}

@Test func globalOptionsFormatJson() throws {
    let options = try GlobalOptions.parse(["--profile", "e2", "https://s3.example.com", "--format", "json"])
    #expect(options.format == .json)
}

@Test func globalOptionsVerbose() throws {
    let options = try GlobalOptions.parse(["--profile", "e2", "https://s3.example.com", "--verbose"])
    #expect(options.verbose == true)
}
