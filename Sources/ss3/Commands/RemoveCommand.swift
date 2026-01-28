import ArgumentParser
import Foundation
import SwiftS3

struct RemoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rm",
        abstract: "Remove a remote file"
    )

    @OptionGroup var options: GlobalOptions

    @Argument(help: "Remote path to delete (profile:bucket/key)")
    var path: String

    func run() async throws {
        let env = Environment()
        let formatter = HumanFormatter()
        let config = try ConfigFile.loadDefault(env: env)

        // Parse and validate path
        let parsed = S3Path.parse(path)
        guard case .remote(let profileName, let bucket, let key) = parsed else {
            throw ValidationError("Path must be remote: profile:bucket/key")
        }
        guard let bucket = bucket else {
            throw ValidationError("Path must include bucket: profile:bucket/key")
        }
        guard let key = key else {
            throw ValidationError("Path must include key: profile:bucket/key")
        }
        guard !key.hasSuffix("/") else {
            throw ValidationError("Cannot delete directories. Path must not end with /")
        }

        // Resolve profile and create client
        let resolver = ProfileResolver(config: config)
        let profile = try resolver.resolve(
            profileName: profileName,
            cliOverride: options.parseProfileOverride()
        )
        let resolved = try profile.resolve(with: env, pathStyle: options.pathStyle)
        let client = ClientFactory.createClient(from: resolved)

        do {
            try await client.deleteObject(bucket: bucket, key: key)
            print(formatter.formatSuccess("Deleted \(bucket)/\(key)"))
        } catch {
            printError(formatter.formatError(error, verbose: options.verbose))
            throw ExitCode(1)
        }
    }
}
