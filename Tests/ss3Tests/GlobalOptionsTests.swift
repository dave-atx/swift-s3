import Testing
import ArgumentParser
@testable import ss3

@Test func globalOptionsResolvesFromFlag() throws {
    let options = try GlobalOptions.parse(["--key-id", "flag-key"])

    let env = Environment(getenv: { _ in "env-key" })
    let resolved = options.resolve(with: env)

    #expect(resolved.keyId == "flag-key")
}

@Test func globalOptionsResolvesFromEnv() throws {
    let options = try GlobalOptions.parse([])
    let env = Environment(getenv: { key in
        if key == "SS3_KEY_ID" { return "env-key" }
        return nil
    })
    let resolved = options.resolve(with: env)

    #expect(resolved.keyId == "env-key")
}

@Test func globalOptionsB2SetsEndpoint() throws {
    let options = try GlobalOptions.parse(["--b2", "--region", "us-west-002"])

    let env = Environment(getenv: { _ in nil })
    let resolved = options.resolve(with: env)

    #expect(resolved.endpoint == "https://s3.us-west-002.backblazeb2.com")
}
