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

        // Parse and validate source
        let srcParsed = S3Path.parse(source)
        guard case .remote(let srcProfile, let srcBucketOpt, let srcKeyOpt) = srcParsed else {
            throw ValidationError("Source must be remote: profile:bucket/key")
        }
        guard let srcBucket = srcBucketOpt else {
            throw ValidationError("Source must include bucket: profile:bucket/key")
        }
        guard let srcKey = srcKeyOpt else {
            throw ValidationError("Source must include key: profile:bucket/key")
        }
        guard !srcKey.hasSuffix("/") else {
            throw ValidationError("Cannot move directories. Source must not end with /")
        }

        // Parse and validate destination
        let dstParsed = S3Path.parse(destination)
        guard case .remote(let dstProfile, let dstBucketOpt, let dstKeyOpt) = dstParsed else {
            throw ValidationError("Destination must be remote: profile:bucket/key")
        }
        guard let dstBucket = dstBucketOpt else {
            throw ValidationError("Destination must include bucket: profile:bucket/key")
        }
        guard let dstKey = dstKeyOpt else {
            throw ValidationError("Destination must include key: profile:bucket/key")
        }
        guard !dstKey.hasSuffix("/") else {
            throw ValidationError("Cannot move to directory. Destination must not end with /")
        }

        // Both paths must use the same profile
        guard srcProfile == dstProfile else {
            throw ValidationError("Source and destination must use the same profile")
        }

        // Resolve profile and create client
        let resolver = ProfileResolver(config: config)
        let profile = try resolver.resolve(
            profileName: srcProfile,
            cliOverride: options.parseProfileOverride()
        )
        let resolved = try profile.resolve(with: env, pathStyle: options.pathStyle)
        let client = ClientFactory.createClient(from: resolved)

        do {
            // Copy then delete (S3 has no native move)
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
}
