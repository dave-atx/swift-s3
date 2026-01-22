import Testing
@testable import ss3

@Test func outputFormatDefaultsToHuman() {
    let format = OutputFormat.human
    #expect(format.rawValue == "human")
}

@Test func outputFormatParsesFromString() {
    #expect(OutputFormat(rawValue: "json") == .json)
    #expect(OutputFormat(rawValue: "tsv") == .tsv)
    #expect(OutputFormat(rawValue: "human") == .human)
    #expect(OutputFormat(rawValue: "invalid") == nil)
}
