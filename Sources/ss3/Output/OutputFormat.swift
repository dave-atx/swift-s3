import ArgumentParser

enum OutputFormat: String, ExpressibleByArgument, CaseIterable, Sendable {
    case human
    case json
    case tsv

    func createFormatter() -> any OutputFormatter {
        switch self {
        case .human: return HumanFormatter()
        case .json: return JSONFormatter()
        case .tsv: return TSVFormatter()
        }
    }
}
