import ArgumentParser
import Foundation
import SwiftS3

struct MoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mv",
        abstract: "Move or rename a remote file"
    )

    @OptionGroup var options: GlobalOptions

    @Argument(help: "Source remote path (profile:bucket/key)")
    var source: String

    @Argument(help: "Destination remote path (profile:bucket/key)")
    var destination: String

    private struct ParsedPath {
        let profile: String
        let bucket: String
        let key: String
    }

    func run() async throws {
        let env = Environment()
        let formatter = HumanFormatter()
        let config = try ConfigFile.loadDefault(env: env)

        let src = try validateSource()
        let dst = try validateDestination()

        guard src.profile == dst.profile else {
            throw ValidationError("Source and destination must use the same profile")
        }

        let client = try createClient(profileName: src.profile, config: config, env: env)

        do {
            _ = try await client.copyObject(
                sourceBucket: src.bucket,
                sourceKey: src.key,
                destinationBucket: dst.bucket,
                destinationKey: dst.key
            )
            try await client.deleteObject(bucket: src.bucket, key: src.key)

            print(formatter.formatSuccess("Moved \(src.bucket)/\(src.key) to \(dst.bucket)/\(dst.key)"))
        } catch {
            printError(formatter.formatError(error, verbose: options.verbose))
            throw ExitCode(1)
        }
    }

    private func validateSource() throws -> ParsedPath {
        let parsed = S3Path.parse(source)
        guard case .remote(let profile, let bucketOpt, let keyOpt) = parsed else {
            throw ValidationError("Source must be remote: profile:bucket/key")
        }
        guard let bucket = bucketOpt else {
            throw ValidationError("Source must include bucket: profile:bucket/key")
        }
        guard let key = keyOpt else {
            throw ValidationError("Source must include key: profile:bucket/key")
        }
        guard !key.hasSuffix("/") else {
            throw ValidationError("Cannot move directories. Source must not end with /")
        }
        return ParsedPath(profile: profile, bucket: bucket, key: key)
    }

    private func validateDestination() throws -> ParsedPath {
        let parsed = S3Path.parse(destination)
        guard case .remote(let profile, let bucketOpt, let keyOpt) = parsed else {
            throw ValidationError("Destination must be remote: profile:bucket/key")
        }
        guard let bucket = bucketOpt else {
            throw ValidationError("Destination must include bucket: profile:bucket/key")
        }
        guard let key = keyOpt else {
            throw ValidationError("Destination must include key: profile:bucket/key")
        }
        guard !key.hasSuffix("/") else {
            throw ValidationError("Cannot move to directory. Destination must not end with /")
        }
        return ParsedPath(profile: profile, bucket: bucket, key: key)
    }

    private func createClient(profileName: String, config: ConfigFile?, env: Environment) throws -> S3Client {
        let resolver = ProfileResolver(config: config)
        let profile = try resolver.resolve(
            profileName: profileName,
            cliOverride: options.parseProfileOverride()
        )
        let resolved = try profile.resolve(with: env, pathStyle: options.pathStyle)
        return ClientFactory.createClient(from: resolved)
    }
}
