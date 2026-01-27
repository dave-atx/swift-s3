import ArgumentParser
import Foundation
import SwiftS3

struct CopyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cp",
        abstract: "Copy files to/from S3"
    )

    @OptionGroup var options: GlobalOptions

    @Argument(help: "Source path (local file or profile:bucket/key)")
    var source: String

    @Argument(help: "Destination path (local file or profile:bucket/key)")
    var destination: String

    @Option(help: "Multipart threshold in bytes (default: 100MB)")
    var multipartThreshold: Int64 = 100 * 1024 * 1024

    @Option(help: "Chunk size in bytes (default: 10MB)")
    var chunkSize: Int64 = 10 * 1024 * 1024

    @Option(help: "Max parallel chunk uploads (default: 4)")
    var parallel: Int = 4

    func run() async throws {
        let env = Environment()
        let formatter = options.format.createFormatter()

        // Load config file (nil if not found)
        let config = try ConfigFile.loadDefault(env: env)

        let sourcePath = S3Path.parse(source)
        let destPath = S3Path.parse(destination)

        guard sourcePath.isLocal != destPath.isLocal else {
            throw ValidationError("Must specify exactly one local and one remote path")
        }

        // Extract profile name from the remote path
        guard let profileName = sourcePath.profile ?? destPath.profile else {
            throw ValidationError("Remote path must include profile: profile:bucket/key")
        }

        // Resolve profile (CLI override or config lookup)
        let resolver = ProfileResolver(config: config)
        let profile = try resolver.resolve(
            profileName: profileName,
            cliOverride: options.parseProfileOverride()
        )

        // Validate path profile matches if --profile was specified
        if let override = options.parseProfileOverride(), override.name != profileName {
            throw ValidationError(
                "Path profile '\(profileName)' doesn't match --profile '\(override.name)'"
            )
        }

        let resolved = try profile.resolve(with: env, pathStyle: options.pathStyle)
        let client = ClientFactory.createClient(from: resolved)

        do {
            if sourcePath.isLocal {
                try await upload(
                    client: client,
                    localPath: sourcePath,
                    remotePath: destPath,
                    resolvedProfile: resolved,
                    formatter: formatter
                )
            } else {
                try await download(
                    client: client,
                    remotePath: sourcePath,
                    localPath: destPath,
                    formatter: formatter
                )
            }
        } catch {
            printError(formatter.formatError(error, verbose: options.verbose))
            throw ExitCode(1)
        }
    }

    private func upload(
        client: S3Client,
        localPath: S3Path,
        remotePath: S3Path,
        resolvedProfile: ResolvedProfile,
        formatter: any OutputFormatter
    ) async throws {
        guard case .local(let filePath) = localPath else {
            throw ValidationError("Expected local source path")
        }
        guard case .remote(_, let bucketOrNil, let keyOrNil) = remotePath else {
            throw ValidationError("Expected remote destination path")
        }

        // Resolve bucket from path or profile
        guard let bucket = bucketOrNil ?? resolvedProfile.bucket else {
            throw ValidationError("No bucket specified. Use profile:bucket/key format")
        }

        let fileURL = URL(fileURLWithPath: filePath)
        let fileName = fileURL.lastPathComponent
        let key = try await resolveUploadKey(
            client: client,
            bucket: bucket,
            keyOrNil: keyOrNil,
            fileName: fileName
        )

        let attributes = try FileManager.default.attributesOfItem(atPath: filePath)
        guard let fileSize = attributes[.size] as? Int64 else {
            throw ValidationError("Cannot determine file size for \(filePath)")
        }

        if fileSize > multipartThreshold {
            let uploader = MultipartUploader(client: client, chunkSize: chunkSize, maxParallel: parallel)
            try await uploader.upload(bucket: bucket, key: key, fileURL: fileURL, fileSize: fileSize)
        } else {
            let data = try Data(contentsOf: fileURL)
            _ = try await client.putObject(bucket: bucket, key: key, data: data)
        }

        print(formatter.formatSuccess("Uploaded \(fileName) to \(bucket)/\(key)"))
    }

    private func download(
        client: S3Client,
        remotePath: S3Path,
        localPath: S3Path,
        formatter: any OutputFormatter
    ) async throws {
        guard case .remote(_, let bucketOrNil, let keyOrNil) = remotePath else {
            throw ValidationError("Expected remote source path")
        }
        guard let bucket = bucketOrNil else {
            throw ValidationError("Remote source must include a bucket")
        }
        guard let key = keyOrNil else {
            throw ValidationError("Remote source must include a key, not just bucket")
        }
        guard case .local(let filePath) = localPath else {
            throw ValidationError("Expected local destination path")
        }

        var destinationURL = URL(fileURLWithPath: filePath)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: filePath, isDirectory: &isDirectory), isDirectory.boolValue {
            destinationURL = destinationURL.appendingPathComponent(URL(fileURLWithPath: key).lastPathComponent)
        }

        _ = try await client.downloadObject(bucket: bucket, key: key, to: destinationURL)
        print(formatter.formatSuccess("Downloaded \(bucket)/\(key) to \(destinationURL.path)"))
    }

    private func resolveUploadKey(
        client: S3Client,
        bucket: String,
        keyOrNil: String?,
        fileName: String
    ) async throws -> String {
        guard let existingKey = keyOrNil else {
            // No key specified - upload to root with filename
            return fileName
        }

        // If key ends with /, treat as directory
        if existingKey.hasSuffix("/") {
            return existingKey + fileName
        }

        // Check if key is a directory by querying S3
        let isDirectory = await checkIfDirectory(client: client, bucket: bucket, prefix: existingKey)
        if isDirectory {
            return existingKey + "/" + fileName
        }

        return existingKey
    }

    private func checkIfDirectory(client: S3Client, bucket: String, prefix: String) async -> Bool {
        do {
            let result = try await client.listObjects(
                bucket: bucket,
                prefix: prefix + "/",
                maxKeys: 1
            )
            return !result.objects.isEmpty || !result.commonPrefixes.isEmpty
        } catch {
            return false
        }
    }
}
