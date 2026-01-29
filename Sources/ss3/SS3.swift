import ArgumentParser

/// Version string: injected at build time via Version.generated.swift for releases, defaults to "dev" for local builds
#if !SS3_VERSION_INJECTED
let ss3Version = "dev"
#endif

@main
struct SS3: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ss3",
        abstract: "A CLI for S3-compatible storage services",
        version: ss3Version,
        subcommands: [ListCommand.self, CopyCommand.self, RemoveCommand.self, TouchCommand.self, MoveCommand.self],
        defaultSubcommand: nil
    )
}
