import ArgumentParser

struct GlobalOptions: ParsableArguments {
    @Option(name: .customLong("profile"), parsing: .upToNextOption, help: "Profile: <name> <url>")
    var profileArgs: [String] = []

    @Flag(help: "Verbose error output")
    var verbose: Bool = false

    @Option(help: "Output format (human, json, tsv)")
    var format: OutputFormat = .human

    func parseProfile() throws -> Profile {
        guard profileArgs.count >= 2 else {
            throw ValidationError("--profile requires two arguments: <name> <url>")
        }
        return try Profile.parse(name: profileArgs[0], url: profileArgs[1])
    }
}
