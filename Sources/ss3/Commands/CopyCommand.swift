import ArgumentParser

struct CopyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cp",
        abstract: "Copy files to/from S3"
    )

    func run() async throws {
        print("cp command not yet implemented")
    }
}
