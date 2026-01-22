import ArgumentParser

enum OutputFormat: String, ExpressibleByArgument, CaseIterable, Sendable {
    case human
    case json
    case tsv
}
