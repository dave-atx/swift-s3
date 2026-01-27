import ArgumentParser

struct GlobalOptions: ParsableArguments {
    @Option(name: .customLong("profile"), parsing: .upToNextOption, help: "Profile: <name> <url>")
    var profileArgs: [String] = []

    @Flag(name: .long, help: "Use path-style addressing (required for minio/local endpoints)")
    var pathStyle: Bool = false

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

    /// Returns CLI profile override if provided (both name and URL).
    /// Returns nil if no --profile flag was used.
    func parseProfileOverride() -> (name: String, url: String)? {
        guard profileArgs.count >= 2 else {
            return nil
        }
        return (name: profileArgs[0], url: profileArgs[1])
    }

    /// Requires --profile to be specified with both name and URL.
    /// Use this when no config file exists.
    func requireProfileOverride() throws -> (name: String, url: String) {
        guard profileArgs.count >= 2 else {
            throw ValidationError("--profile requires two arguments: <name> <url>")
        }
        return (name: profileArgs[0], url: profileArgs[1])
    }
}
