import ArgumentParser
import Foundation
import SwiftS3

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ls",
        abstract: "List buckets or objects"
    )

    @OptionGroup var options: GlobalOptions

    @Argument(help: "Bucket name or bucket/prefix to list")
    var path: String?

    func run() async throws {
        let env = Environment()
        let config = options.resolve(with: env)
        let formatter = config.format.createFormatter()

        // Validate required credentials
        guard let keyId = config.keyId else {
            throw ValidationError("Missing key ID. Use --key-id or set SS3_KEY_ID")
        }
        guard let secretKey = config.secretKey else {
            throw ValidationError("Missing secret key. Use --secret-key or set SS3_SECRET_KEY")
        }
        guard let region = config.region else {
            throw ValidationError("Missing region. Use --region or set SS3_REGION")
        }
        guard let endpoint = config.endpoint else {
            throw ValidationError("Missing endpoint. Use --endpoint or set SS3_ENDPOINT")
        }
        guard let endpointURL = URL(string: endpoint) else {
            throw ValidationError("Invalid endpoint URL: \(endpoint)")
        }

        let s3Config = S3Configuration(
            accessKeyId: keyId,
            secretAccessKey: secretKey,
            region: region,
            endpoint: endpointURL
        )
        let client = S3Client(configuration: s3Config)

        do {
            if let path = path ?? config.bucket {
                // List objects in bucket
                try await listObjects(client: client, path: path, formatter: formatter)
            } else {
                // List all buckets
                try await listBuckets(client: client, formatter: formatter)
            }
        } catch {
            printError(formatter.formatError(error, verbose: config.verbose))
            throw ExitCode(1)
        }
    }

    private func listBuckets(client: S3Client, formatter: any OutputFormatter) async throws {
        let result = try await client.listBuckets()
        print(formatter.formatBuckets(result.buckets))
    }

    private func listObjects(
        client: S3Client,
        path: String,
        formatter: any OutputFormatter
    ) async throws {
        let parsed = S3Path.parse(path)

        guard case .remote(let bucket, let prefix) = parsed else {
            throw ValidationError("Path must be a bucket or bucket/prefix, got local path: \(path)")
        }

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
