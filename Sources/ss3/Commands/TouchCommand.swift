import ArgumentParser
import Foundation
import SwiftS3

struct TouchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "touch",
        abstract: "Create an empty remote file"
    )

    @OptionGroup var options: GlobalOptions

    @Argument(help: "Remote path to create (profile:bucket/key)")
    var path: String

    func run() async throws {
        let env = Environment()
        let formatter = options.format.createFormatter()
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
            throw ValidationError("Cannot create directory. Path must not end with /")
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
            // Check if file already exists
            do {
                _ = try await client.headObject(bucket: bucket, key: key)
                // File exists - error
                throw ValidationError("File already exists: \(bucket)/\(key)")
            } catch let error as S3APIError where error.code == .noSuchKey {
                // File doesn't exist - good, proceed
            }

            // Create empty file
            _ = try await client.putObject(bucket: bucket, key: key, data: Data())
            print(formatter.formatSuccess("Created \(bucket)/\(key)"))
        } catch let error as ValidationError {
            printError(formatter.formatError(error, verbose: options.verbose))
            throw ExitCode(1)
        } catch {
            printError(formatter.formatError(error, verbose: options.verbose))
            throw ExitCode(1)
        }
    }
}
