import ArgumentParser

@main
struct SS3: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ss3",
        abstract: "A CLI for S3-compatible storage services",
        version: "0.1.0",
        subcommands: [ListCommand.self, CopyCommand.self, RemoveCommand.self],
        defaultSubcommand: nil
    )
}
