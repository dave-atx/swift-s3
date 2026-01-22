import ArgumentParser

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ls",
        abstract: "List buckets or objects"
    )

    func run() async throws {
        print("ls command not yet implemented")
    }
}
