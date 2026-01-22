import Testing
@testable import ss3

@Test func environmentReadsKeyId() {
    let env = Environment(getenv: { key in
        if key == "SS3_KEY_ID" { return "test-key" }
        return nil
    })
    #expect(env.keyId == "test-key")
}

@Test func environmentReadsAllVariables() {
    let env = Environment(getenv: { key in
        switch key {
        case "SS3_KEY_ID": return "key123"
        case "SS3_SECRET_KEY": return "secret456"
        case "SS3_REGION": return "us-west-2"
        case "SS3_ENDPOINT": return "https://s3.example.com"
        case "SS3_BUCKET": return "mybucket"
        default: return nil
        }
    })
    #expect(env.keyId == "key123")
    #expect(env.secretKey == "secret456")
    #expect(env.region == "us-west-2")
    #expect(env.endpoint == "https://s3.example.com")
    #expect(env.bucket == "mybucket")
}

@Test func environmentReturnsNilForMissing() {
    let env = Environment(getenv: { _ in nil })
    #expect(env.keyId == nil)
    #expect(env.secretKey == nil)
}
