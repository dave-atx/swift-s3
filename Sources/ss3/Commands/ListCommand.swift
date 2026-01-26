import ArgumentParser
import Foundation
import SwiftS3

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ls",
        abstract: "List buckets or objects"
    )

    @OptionGroup var options: GlobalOptions

    @Argument(help: "Path to list (profile: or profile:bucket/prefix)")
    var path: String?

    func run() async throws {
        let env = Environment()
        let formatter = options.format.createFormatter()

        // Load config file (nil if not found)
        let config = try ConfigFile.loadDefault(env: env)

        // Extract profile name from path
        let profileName: String
        let bucket: String?
        let prefix: String?

        if let path = path {
            let parsed = S3Path.parse(path)
            guard case .remote(let pathProfile, let pathBucket, let pathPrefix) = parsed else {
                throw ValidationError("Path must use profile format: profile:bucket/prefix")
            }
            profileName = pathProfile
            bucket = pathBucket
            prefix = pathPrefix
        } else {
            // No path - need profile from CLI or error
            guard let override = options.parseProfileOverride() else {
                let available = config?.availableProfiles ?? []
                if available.isEmpty {
                    throw ValidationError(
                        "No path specified. Use: ss3 ls <profile>: or ss3 ls <profile>:<bucket>"
                    )
                }
                throw ValidationError(
                    "No path specified. Available profiles: \(available.joined(separator: ", "))"
                )
            }
            profileName = override.name
            bucket = nil
            prefix = nil
        }

        // Resolve profile (CLI override or config lookup)
        let resolver = ProfileResolver(config: config)
        let profile = try resolver.resolve(
            profileName: profileName,
            cliOverride: options.parseProfileOverride()
        )
        let resolved = try profile.resolve(with: env, pathStyle: options.pathStyle)
        let client = ClientFactory.createClient(from: resolved)

        do {
            if let bucket = bucket {
                try await listObjects(
                    client: client,
                    bucket: bucket,
                    prefix: prefix,
                    formatter: formatter
                )
            } else {
                try await listBuckets(client: client, formatter: formatter)
            }
        } catch {
            printError(formatter.formatError(error, verbose: options.verbose))
            throw ExitCode(1)
        }
    }

    private func listBuckets(client: S3Client, formatter: any OutputFormatter) async throws {
        let result = try await client.listBuckets()
        print(formatter.formatBuckets(result.buckets))
    }

    private func listObjects(
        client: S3Client,
        bucket: String,
        prefix: String?,
        formatter: any OutputFormatter
    ) async throws {
        var allObjects: [S3Object] = []
        var allPrefixes: [String] = []
        var continuationToken: String?

        repeat {
            let result = try await client.listObjects(
                bucket: bucket,
                prefix: prefix,
                delimiter: "/",
                continuationToken: continuationToken
            )

            allObjects.append(contentsOf: result.objects)
            allPrefixes.append(contentsOf: result.commonPrefixes)
            continuationToken = result.isTruncated ? result.continuationToken : nil
        } while continuationToken != nil

        print(formatter.formatObjects(allObjects, prefixes: allPrefixes))
    }
}

func printError(_ string: String) {
    FileHandle.standardError.write(Data((string + "\n").utf8))
}
