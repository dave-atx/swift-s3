import ArgumentParser
import Foundation
import SwiftS3

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ls",
        abstract: "List buckets or objects"
    )

    @OptionGroup var options: GlobalOptions

    @Flag(name: .shortAndLong, help: "Long format (size, date, name)")
    var long: Bool = false

    @Flag(name: .short, help: "Long format (synonym for -l)")
    var human: Bool = false

    @Flag(name: .shortAndLong, help: "Sort by modification time, most recent first")
    var time: Bool = false

    @Argument(help: "Path to list (profile: or profile:bucket/prefix)")
    var path: String?

    func run() async throws {
        let env = Environment()
        let longFormat = long || human
        let formatter = ListFormatter(longFormat: longFormat, sortByTime: time)
        let config = try ConfigFile.loadDefault(env: env)

        let pathComponents = try extractPathComponents(config: config)

        let resolver = ProfileResolver(config: config)
        let profile = try resolver.resolve(
            profileName: pathComponents.profileName,
            cliOverride: options.parseProfileOverride()
        )
        let resolved = try profile.resolve(with: env, pathStyle: options.pathStyle)
        let client = ClientFactory.createClient(from: resolved)

        do {
            if let bucket = pathComponents.bucket {
                try await listObjects(
                    client: client,
                    bucket: bucket,
                    prefix: pathComponents.prefix,
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

    private struct PathComponents {
        let profileName: String
        let bucket: String?
        let prefix: String?
    }

    private func extractPathComponents(config: ConfigFile?) throws -> PathComponents {
        if let path = path {
            let parsed = S3Path.parse(path)
            guard case .remote(let pathProfile, let pathBucket, let pathPrefix) = parsed else {
                throw ValidationError("Path must use profile format: profile:bucket/prefix")
            }
            return PathComponents(profileName: pathProfile, bucket: pathBucket, prefix: pathPrefix)
        }

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
        return PathComponents(profileName: override.name, bucket: nil, prefix: nil)
    }

    private func listBuckets(client: S3Client, formatter: ListFormatter) async throws {
        let result = try await client.listBuckets()
        let output = formatter.formatBuckets(result.buckets)
        if !output.isEmpty {
            print(output)
        }
    }

    private func listObjects(
        client: S3Client,
        bucket: String,
        prefix: String?,
        formatter: ListFormatter
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

        let output = formatter.formatObjects(allObjects, prefixes: allPrefixes)
        if !output.isEmpty {
            print(output)
        }
    }
}

func printError(_ string: String) {
    FileHandle.standardError.write(Data((string + "\n").utf8))
}
