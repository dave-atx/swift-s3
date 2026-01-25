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
        let profile = try options.parseProfile()
        let env = Environment()
        let resolved = try profile.resolve(with: env)
        let formatter = options.format.createFormatter()
        let client = ClientFactory.createClient(from: resolved)

        do {
            if let path = path {
                let parsed = S3Path.parse(path)
                guard case .remote(let pathProfile, let bucket, let prefix) = parsed else {
                    throw ValidationError("Path must use profile format: \(profile.name):bucket/prefix")
                }

                guard pathProfile == profile.name else {
                    throw ValidationError("Path profile '\(pathProfile)' doesn't match --profile '\(profile.name)'")
                }

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
