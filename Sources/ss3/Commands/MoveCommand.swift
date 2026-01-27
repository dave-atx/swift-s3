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

    func run() async throws {
        let env = Environment()
        let formatter = options.format.createFormatter()
        let config = try ConfigFile.loadDefault(env: env)

        let (srcProfile, srcBucket, srcKey) = try validateSource()
        let (dstProfile, dstBucket, dstKey) = try validateDestination()

        guard srcProfile == dstProfile else {
            throw ValidationError("Source and destination must use the same profile")
        }

        let client = try createClient(profileName: srcProfile, config: config, env: env)

        do {
            _ = try await client.copyObject(
                sourceBucket: srcBucket,
                sourceKey: srcKey,
                destinationBucket: dstBucket,
                destinationKey: dstKey
            )
            try await client.deleteObject(bucket: srcBucket, key: srcKey)

            print(formatter.formatSuccess("Moved \(srcBucket)/\(srcKey) to \(dstBucket)/\(dstKey)"))
        } catch {
            printError(formatter.formatError(error, verbose: options.verbose))
            throw ExitCode(1)
        }
    }

    private func validateSource() throws -> (profile: String, bucket: String, key: String) {
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
        return (profile, bucket, key)
    }

    private func validateDestination() throws -> (profile: String, bucket: String, key: String) {
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
        return (profile, bucket, key)
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
