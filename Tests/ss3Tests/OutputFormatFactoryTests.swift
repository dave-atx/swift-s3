import Testing
@testable import ss3

@Test func outputFormatCreatesHumanFormatter() {
    let formatter = OutputFormat.human.createFormatter()
    #expect(formatter is HumanFormatter)
}

@Test func outputFormatCreatesJSONFormatter() {
    let formatter = OutputFormat.json.createFormatter()
    #expect(formatter is JSONFormatter)
}

@Test func outputFormatCreatesTSVFormatter() {
    let formatter = OutputFormat.tsv.createFormatter()
    #expect(formatter is TSVFormatter)
}
