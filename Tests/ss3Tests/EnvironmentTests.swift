import Testing
@testable import ss3

@Test func environmentReadsKeyId() {
    let env = Environment(getenv: { key in
        if key == "SS3_ACCESS_KEY" { return "test-key" }
        return nil
    })
    #expect(env.value(for: "SS3_ACCESS_KEY") == "test-key")
}

@Test func environmentReadsAllVariables() {
    let env = Environment(getenv: { key in
        switch key {
        case "SS3_ACCESS_KEY": return "key123"
        case "SS3_SECRET_KEY": return "secret456"
        case "SS3_REGION": return "us-west-2"
        case "SS3_ENDPOINT": return "https://s3.example.com"
        case "SS3_BUCKET": return "mybucket"
        default: return nil
        }
    })
    #expect(env.value(for: "SS3_ACCESS_KEY") == "key123")
    #expect(env.value(for: "SS3_SECRET_KEY") == "secret456")
    #expect(env.value(for: "SS3_REGION") == "us-west-2")
    #expect(env.value(for: "SS3_ENDPOINT") == "https://s3.example.com")
    #expect(env.value(for: "SS3_BUCKET") == "mybucket")
}

@Test func environmentReturnsNilForMissing() {
    let env = Environment(getenv: { _ in nil })
    #expect(env.value(for: "SS3_ACCESS_KEY") == nil)
    #expect(env.value(for: "SS3_SECRET_KEY") == nil)
}
