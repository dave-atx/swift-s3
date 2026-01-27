# Config File Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add config file support at `$XDG_CONFIG_HOME/ss3/profiles.json` to enable shorter CLI commands without `--profile` flags.

**Architecture:** New `ConfigFile` struct loads JSON profile mappings. Commands extract profile name from path, look up URL in config (unless `--profile` overrides). Credential resolution: env vars override URL credentials.

**Tech Stack:** Swift 6.2, Foundation JSONDecoder, Swift Testing framework

---

## Task 1: ConfigFile - Basic Loading

**Files:**
- Create: `Sources/ss3/Configuration/ConfigFile.swift`
- Create: `Tests/ss3Tests/ConfigFileTests.swift`

**Step 1: Write the failing test for basic parsing**

```swift
// Tests/ss3Tests/ConfigFileTests.swift
import Testing
import Foundation
@testable import ss3

@Test func configFileParsesSingleProfile() throws {
    let json = """
    {
      "e2": "https://s3.example.com"
    }
    """
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID()).json")
    try json.write(to: tempFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let config = try ConfigFile.load(from: tempFile.path)

    #expect(config != nil)
    #expect(config?.profileURL(for: "e2") == "https://s3.example.com")
    #expect(config?.profileURL(for: "unknown") == nil)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter ss3Tests.ConfigFileTests/configFileParsesSingleProfile`
Expected: FAIL with "type 'ConfigFile' has no member 'load'"

**Step 3: Write minimal implementation**

```swift
// Sources/ss3/Configuration/ConfigFile.swift
import Foundation

enum ConfigFileError: Error, CustomStringConvertible {
    case malformedJSON(path: String, underlying: Error)
    case unreadable(path: String, underlying: Error)

    var description: String {
        switch self {
        case .malformedJSON(let path, let underlying):
            return "Malformed config file at \(path): \(underlying.localizedDescription)"
        case .unreadable(let path, let underlying):
            return "Cannot read config file at \(path): \(underlying.localizedDescription)"
        }
    }
}

struct ConfigFile: Sendable {
    private let profiles: [String: String]

    init(profiles: [String: String]) {
        self.profiles = profiles
    }

    static func load(from path: String) throws -> ConfigFile? {
        let url = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ConfigFileError.unreadable(path: path, underlying: error)
        }

        do {
            let profiles = try JSONDecoder().decode([String: String].self, from: data)
            return ConfigFile(profiles: profiles)
        } catch {
            throw ConfigFileError.malformedJSON(path: path, underlying: error)
        }
    }

    func profileURL(for name: String) -> String? {
        profiles[name]
    }

    var availableProfiles: [String] {
        profiles.keys.sorted()
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter ss3Tests.ConfigFileTests/configFileParsesSingleProfile`
Expected: PASS

**Step 5: Lint and commit**

```bash
swiftlint --fix && swiftlint --strict
git add Sources/ss3/Configuration/ConfigFile.swift Tests/ss3Tests/ConfigFileTests.swift
git commit -m "feat(config): add ConfigFile with basic JSON loading"
```

---

## Task 2: ConfigFile - Multiple Profiles and Edge Cases

**Files:**
- Modify: `Tests/ss3Tests/ConfigFileTests.swift`

**Step 1: Write tests for multiple profiles**

```swift
@Test func configFileParsesMultipleProfiles() throws {
    let json = """
    {
      "e2": "https://key:secret@s3.example.com",
      "r2": "https://r2.cloudflare.com",
      "b2": "https://s3.us-west-001.backblaze.com"
    }
    """
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID()).json")
    try json.write(to: tempFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let config = try ConfigFile.load(from: tempFile.path)

    #expect(config?.profileURL(for: "e2") == "https://key:secret@s3.example.com")
    #expect(config?.profileURL(for: "r2") == "https://r2.cloudflare.com")
    #expect(config?.profileURL(for: "b2") == "https://s3.us-west-001.backblaze.com")
    #expect(config?.availableProfiles == ["b2", "e2", "r2"])
}

@Test func configFileReturnsNilForMissingFile() throws {
    let config = try ConfigFile.load(from: "/nonexistent/path/profiles.json")
    #expect(config == nil)
}

@Test func configFileHandlesEmptyFile() throws {
    let json = "{}"
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID()).json")
    try json.write(to: tempFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let config = try ConfigFile.load(from: tempFile.path)

    #expect(config != nil)
    #expect(config?.availableProfiles.isEmpty == true)
}

@Test func configFileThrowsForMalformedJSON() throws {
    let badJson = "{ not valid json }"
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID()).json")
    try badJson.write(to: tempFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    #expect(throws: ConfigFileError.self) {
        try ConfigFile.load(from: tempFile.path)
    }
}
```

**Step 2: Run tests to verify they pass**

Run: `swift test --filter ss3Tests.ConfigFileTests`
Expected: All PASS (implementation already handles these cases)

**Step 3: Lint and commit**

```bash
swiftlint --fix && swiftlint --strict
git add Tests/ss3Tests/ConfigFileTests.swift
git commit -m "test(config): add ConfigFile edge case tests"
```

---

## Task 3: ConfigFile - XDG Path Resolution

**Files:**
- Modify: `Sources/ss3/Configuration/ConfigFile.swift`
- Modify: `Tests/ss3Tests/ConfigFileTests.swift`

**Step 1: Write test for default path resolution**

```swift
@Test func configFileDefaultPathUsesXDGConfigHome() {
    let env = Environment(getenv: { key in
        if key == "XDG_CONFIG_HOME" { return "/custom/config" }
        return nil
    })
    let path = ConfigFile.defaultPath(env: env)
    #expect(path == "/custom/config/ss3/profiles.json")
}

@Test func configFileDefaultPathFallsBackToHomeConfig() {
    let env = Environment(getenv: { key in
        if key == "HOME" { return "/home/testuser" }
        return nil
    })
    let path = ConfigFile.defaultPath(env: env)
    #expect(path == "/home/testuser/.config/ss3/profiles.json")
}

@Test func configFileDefaultPathReturnsNilWithoutHome() {
    let env = Environment(getenv: { _ in nil })
    let path = ConfigFile.defaultPath(env: env)
    #expect(path == nil)
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter ss3Tests.ConfigFileTests/configFileDefaultPath`
Expected: FAIL with "type 'ConfigFile' has no member 'defaultPath'"

**Step 3: Add defaultPath implementation**

Add to `Sources/ss3/Configuration/ConfigFile.swift`:

```swift
    static func defaultPath(env: Environment = Environment()) -> String? {
        if let xdgConfig = env.value(for: "XDG_CONFIG_HOME") {
            return "\(xdgConfig)/ss3/profiles.json"
        }
        if let home = env.value(for: "HOME") {
            return "\(home)/.config/ss3/profiles.json"
        }
        return nil
    }

    static func loadDefault(env: Environment = Environment()) throws -> ConfigFile? {
        guard let path = defaultPath(env: env) else {
            return nil
        }
        return try load(from: path)
    }
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter ss3Tests.ConfigFileTests`
Expected: All PASS

**Step 5: Lint and commit**

```bash
swiftlint --fix && swiftlint --strict
git add Sources/ss3/Configuration/ConfigFile.swift Tests/ss3Tests/ConfigFileTests.swift
git commit -m "feat(config): add XDG config path resolution"
```

---

## Task 4: ProfileResolver - Core Logic

**Files:**
- Create: `Sources/ss3/Configuration/ProfileResolver.swift`
- Create: `Tests/ss3Tests/ProfileResolverTests.swift`

**Step 1: Write test for profile resolution from config**

```swift
// Tests/ss3Tests/ProfileResolverTests.swift
import Testing
import Foundation
@testable import ss3

@Test func profileResolverLooksUpFromConfig() throws {
    let config = ConfigFile(profiles: ["e2": "https://s3.example.com"])
    let resolver = ProfileResolver(config: config)

    let profile = try resolver.resolve(profileName: "e2", cliOverride: nil)

    #expect(profile.name == "e2")
    #expect(profile.endpoint.absoluteString == "https://s3.example.com")
}

@Test func profileResolverCLIOverrideWins() throws {
    let config = ConfigFile(profiles: ["e2": "https://config.example.com"])
    let resolver = ProfileResolver(config: config)

    let profile = try resolver.resolve(
        profileName: "e2",
        cliOverride: (name: "e2", url: "https://cli.example.com")
    )

    #expect(profile.endpoint.absoluteString == "https://cli.example.com")
}

@Test func profileResolverThrowsForUnknownProfile() throws {
    let config = ConfigFile(profiles: ["e2": "https://s3.example.com"])
    let resolver = ProfileResolver(config: config)

    #expect(throws: ProfileResolverError.self) {
        try resolver.resolve(profileName: "unknown", cliOverride: nil)
    }
}

@Test func profileResolverErrorShowsAvailableProfiles() throws {
    let config = ConfigFile(profiles: [
        "b2": "https://b2.example.com",
        "e2": "https://e2.example.com",
        "r2": "https://r2.example.com"
    ])
    let resolver = ProfileResolver(config: config)

    do {
        _ = try resolver.resolve(profileName: "unknown", cliOverride: nil)
        Issue.record("Expected error to be thrown")
    } catch let error as ProfileResolverError {
        let description = error.description
        #expect(description.contains("unknown"))
        #expect(description.contains("b2"))
        #expect(description.contains("e2"))
        #expect(description.contains("r2"))
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter ss3Tests.ProfileResolverTests`
Expected: FAIL with "cannot find type 'ProfileResolver'"

**Step 3: Write ProfileResolver implementation**

```swift
// Sources/ss3/Configuration/ProfileResolver.swift
import Foundation

enum ProfileResolverError: Error, CustomStringConvertible {
    case unknownProfile(name: String, available: [String])
    case noConfig(profileName: String)

    var description: String {
        switch self {
        case .unknownProfile(let name, let available):
            if available.isEmpty {
                return "Unknown profile '\(name)'. No config file found.\n" +
                       "Use --profile <name> <url> to specify endpoint."
            }
            return "Unknown profile '\(name)'. Available profiles: \(available.joined(separator: ", "))\n" +
                   "Use --profile <name> <url> to specify endpoint."
        case .noConfig(let profileName):
            return "Unknown profile '\(profileName)'. No config file found.\n" +
                   "Use --profile <name> <url> to specify endpoint."
        }
    }
}

struct ProfileResolver: Sendable {
    let config: ConfigFile?

    init(config: ConfigFile?) {
        self.config = config
    }

    func resolve(
        profileName: String,
        cliOverride: (name: String, url: String)?
    ) throws -> Profile {
        // CLI override takes precedence
        if let override = cliOverride, override.name == profileName {
            return try Profile.parse(name: override.name, url: override.url)
        }

        // Look up in config
        guard let config = config else {
            throw ProfileResolverError.noConfig(profileName: profileName)
        }

        guard let url = config.profileURL(for: profileName) else {
            throw ProfileResolverError.unknownProfile(
                name: profileName,
                available: config.availableProfiles
            )
        }

        return try Profile.parse(name: profileName, url: url)
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter ss3Tests.ProfileResolverTests`
Expected: All PASS

**Step 5: Lint and commit**

```bash
swiftlint --fix && swiftlint --strict
git add Sources/ss3/Configuration/ProfileResolver.swift Tests/ss3Tests/ProfileResolverTests.swift
git commit -m "feat(config): add ProfileResolver for config-based lookups"
```

---

## Task 5: ProfileResolver - No Config File Case

**Files:**
- Modify: `Tests/ss3Tests/ProfileResolverTests.swift`

**Step 1: Write test for nil config behavior**

```swift
@Test func profileResolverWithNilConfigRequiresCLIOverride() throws {
    let resolver = ProfileResolver(config: nil)

    // Should fail without CLI override
    #expect(throws: ProfileResolverError.self) {
        try resolver.resolve(profileName: "e2", cliOverride: nil)
    }

    // Should succeed with CLI override
    let profile = try resolver.resolve(
        profileName: "e2",
        cliOverride: (name: "e2", url: "https://s3.example.com")
    )
    #expect(profile.name == "e2")
}
```

**Step 2: Run tests to verify they pass**

Run: `swift test --filter ss3Tests.ProfileResolverTests`
Expected: All PASS (already implemented)

**Step 3: Commit**

```bash
git add Tests/ss3Tests/ProfileResolverTests.swift
git commit -m "test(config): add ProfileResolver nil config tests"
```

---

## Task 6: Update GlobalOptions - Parse CLI Override

**Files:**
- Modify: `Sources/ss3/Configuration/GlobalOptions.swift`
- Modify: `Tests/ss3Tests/GlobalOptionsTests.swift`

**Step 1: Write test for parseProfileOverride**

```swift
// Add to Tests/ss3Tests/GlobalOptionsTests.swift
@Test func globalOptionsParseProfileOverrideWithBothArgs() throws {
    var options = GlobalOptions()
    options.profileArgs = ["e2", "https://s3.example.com"]

    let override = options.parseProfileOverride()

    #expect(override?.name == "e2")
    #expect(override?.url == "https://s3.example.com")
}

@Test func globalOptionsParseProfileOverrideReturnsNilWhenEmpty() throws {
    var options = GlobalOptions()
    options.profileArgs = []

    let override = options.parseProfileOverride()

    #expect(override == nil)
}

@Test func globalOptionsParseProfileOverrideThrowsWithOneArg() throws {
    var options = GlobalOptions()
    options.profileArgs = ["e2"]

    #expect(throws: ValidationError.self) {
        _ = try options.requireProfileOverride()
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter ss3Tests.GlobalOptionsTests/globalOptionsParseProfileOverride`
Expected: FAIL with "has no member 'parseProfileOverride'"

**Step 3: Add parseProfileOverride to GlobalOptions**

Modify `Sources/ss3/Configuration/GlobalOptions.swift`:

```swift
import ArgumentParser

struct GlobalOptions: ParsableArguments {
    @Option(name: .customLong("profile"), parsing: .upToNextOption, help: "Profile: <name> <url>")
    var profileArgs: [String] = []

    @Flag(name: .long, help: "Use path-style addressing (required for minio/local endpoints)")
    var pathStyle: Bool = false

    @Flag(help: "Verbose error output")
    var verbose: Bool = false

    @Option(help: "Output format (human, json, tsv)")
    var format: OutputFormat = .human

    /// Returns CLI profile override if provided (both name and URL).
    /// Returns nil if no --profile flag was used.
    func parseProfileOverride() -> (name: String, url: String)? {
        guard profileArgs.count >= 2 else {
            return nil
        }
        return (name: profileArgs[0], url: profileArgs[1])
    }

    /// Requires --profile to be specified with both name and URL.
    /// Use this when no config file exists.
    func requireProfileOverride() throws -> (name: String, url: String) {
        guard profileArgs.count >= 2 else {
            throw ValidationError("--profile requires two arguments: <name> <url>")
        }
        return (name: profileArgs[0], url: profileArgs[1])
    }

    // Keep legacy method for backward compatibility during migration
    func parseProfile() throws -> Profile {
        guard profileArgs.count >= 2 else {
            throw ValidationError("--profile requires two arguments: <name> <url>")
        }
        return try Profile.parse(name: profileArgs[0], url: profileArgs[1])
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter ss3Tests.GlobalOptionsTests`
Expected: All PASS

**Step 5: Lint and commit**

```bash
swiftlint --fix && swiftlint --strict
git add Sources/ss3/Configuration/GlobalOptions.swift Tests/ss3Tests/GlobalOptionsTests.swift
git commit -m "feat(config): add parseProfileOverride to GlobalOptions"
```

---

## Task 7: Update ListCommand - Config-Based Profile Resolution

**Files:**
- Modify: `Sources/ss3/Commands/ListCommand.swift`

**Step 1: Read current implementation and understand the changes needed**

The command currently calls `options.parseProfile()` which requires `--profile`. We need to:
1. Load config file
2. Extract profile name from path argument
3. Use ProfileResolver to get profile (CLI override or config lookup)

**Step 2: Update ListCommand implementation**

```swift
// Sources/ss3/Commands/ListCommand.swift
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
```

**Step 3: Build to verify compilation**

Run: `swift build`
Expected: Build succeeds

**Step 4: Lint and commit**

```bash
swiftlint --fix && swiftlint --strict
git add Sources/ss3/Commands/ListCommand.swift
git commit -m "feat(ls): update to use config-based profile resolution"
```

---

## Task 8: Update CopyCommand - Config-Based Profile Resolution

**Files:**
- Modify: `Sources/ss3/Commands/CopyCommand.swift`

**Step 1: Update CopyCommand implementation**

Apply the same pattern as ListCommand:

```swift
// Sources/ss3/Commands/CopyCommand.swift
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
```

**Step 2: Build to verify compilation**

Run: `swift build`
Expected: Build succeeds

**Step 3: Lint and commit**

```bash
swiftlint --fix && swiftlint --strict
git add Sources/ss3/Commands/CopyCommand.swift
git commit -m "feat(cp): update to use config-based profile resolution"
```

---

## Task 9: Update CLIRunner for Integration Tests

**Files:**
- Modify: `Tests/ss3IntegrationTests/CLIRunner.swift`

**Step 1: Update CLIRunner to support config file in tests**

The integration tests need to work with a config file. Add support for running with a temp config:

```swift
// Tests/ss3IntegrationTests/CLIRunner.swift
import Foundation

/// Result of running an ss3 CLI command.
struct CLIResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }
}

/// Runs the ss3 CLI binary and captures output.
enum CLIRunner {
    /// Profile name used for minio tests.
    static let profileName = "minio"

    /// Profile URL for minio test server.
    static var profileURL: String {
        let endpoint = MinioTestServer.endpoint
        let credentials = "\(MinioTestServer.accessKey):\(MinioTestServer.secretKey)"
        return endpoint.replacingOccurrences(of: "http://", with: "http://\(credentials)@")
    }

    /// Path to the built ss3 binary.
    static var binaryPath: String {
        // Swift test runs from package directory, binary is in .build/debug/
        let possiblePaths = [
            ".build/debug/ss3",
            "../.build/debug/ss3",
            "../../.build/debug/ss3"
        ]

        for path in possiblePaths where FileManager.default.fileExists(atPath: path) {
            return path
        }

        // Fall back to building the path from current directory
        let cwd = FileManager.default.currentDirectoryPath
        return "\(cwd)/.build/debug/ss3"
    }

    /// Profile arguments for CLI invocation.
    static var profileArgs: [String] {
        ["--profile", profileName, profileURL, "--path-style"]
    }

    /// Creates a temporary config file for testing.
    static func createTempConfig() throws -> URL {
        let configDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ss3-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        let configFile = configDir.appendingPathComponent("profiles.json")
        let config = """
        {
          "\(profileName)": "\(profileURL)"
        }
        """
        try config.write(to: configFile, atomically: true, encoding: .utf8)
        return configDir
    }

    /// Runs ss3 with the given arguments.
    /// - Parameters:
    ///   - args: Command line arguments (e.g., "ls", "minio:bucket")
    ///   - env: Additional environment variables
    ///   - useConfig: If true, use config file instead of --profile flag
    /// - Returns: CLIResult with exit code and captured output
    static func run(_ args: String..., env: [String: String] = [:], useConfig: Bool = false) async throws -> CLIResult {
        try await run(arguments: args, env: env, useConfig: useConfig)
    }

    /// Runs ss3 with the given arguments array.
    /// Arguments: first arg is the subcommand, profile options are inserted after it.
    static func run(
        arguments: [String],
        env: [String: String] = [:],
        useConfig: Bool = false
    ) async throws -> CLIResult {
        var fullArgs: [String] = []
        var environment = ProcessInfo.processInfo.environment

        // Add custom env vars
        for (key, value) in env {
            environment[key] = value
        }

        if useConfig {
            // Create temp config file and set XDG_CONFIG_HOME
            let configDir = try createTempConfig()
            environment["XDG_CONFIG_HOME"] = configDir.path

            // Just use the arguments as-is (profile from config), add --path-style
            if let subcommand = arguments.first {
                fullArgs.append(subcommand)
                fullArgs.append("--path-style")
                fullArgs.append(contentsOf: arguments.dropFirst())
            }
        } else {
            // Use --profile flag (existing behavior)
            if let subcommand = arguments.first {
                fullArgs.append(subcommand)
                fullArgs.append(contentsOf: profileArgs)
                fullArgs.append(contentsOf: arguments.dropFirst())
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = fullArgs
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return CLIResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}
```

**Step 2: Build to verify compilation**

Run: `swift build`
Expected: Build succeeds

**Step 3: Lint and commit**

```bash
swiftlint --fix && swiftlint --strict
git add Tests/ss3IntegrationTests/CLIRunner.swift
git commit -m "test(cli): add config file support to CLIRunner"
```

---

## Task 10: Integration Tests - Config File Usage

**Files:**
- Create: `Tests/ss3IntegrationTests/ConfigFileIntegrationTests.swift`

**Step 1: Write integration tests for config file usage**

```swift
// Tests/ss3IntegrationTests/ConfigFileIntegrationTests.swift
import Testing
import Foundation
import SwiftS3

@Suite("Config File Integration", .serialized)
struct ConfigFileIntegrationTests {
    init() async throws {
        try await MinioTestServer.shared.ensureRunning()
    }

    @Test func listBucketsWithConfigFile() async throws {
        let client = CLITestConfig.createClient()
        let bucket = CLITestConfig.uniqueBucketName(prefix: "cfglist")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucketViaCLI(bucket) } }

        // Run with config file instead of --profile flag
        let result = try await CLIRunner.run("ls", "minio:", useConfig: true)

        #expect(result.succeeded)
        #expect(result.stdout.contains(bucket))
    }

    @Test func listObjectsWithConfigFile() async throws {
        let client = CLITestConfig.createClient()
        let bucket = CLITestConfig.uniqueBucketName(prefix: "cfgobj")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucketViaCLI(bucket) } }

        _ = try await client.putObject(bucket: bucket, key: "test.txt", data: Data("test".utf8))

        let result = try await CLIRunner.run("ls", "minio:\(bucket)/", useConfig: true)

        #expect(result.succeeded)
        #expect(result.stdout.contains("test.txt"))
    }

    @Test func copyWithConfigFile() async throws {
        let client = CLITestConfig.createClient()
        let bucket = CLITestConfig.uniqueBucketName(prefix: "cfgcp")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucketViaCLI(bucket) } }

        // Create temp file
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-\(UUID().uuidString).txt")
        try "config file test".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let result = try await CLIRunner.run(
            "cp", tempFile.path, "minio:\(bucket)/uploaded.txt",
            useConfig: true
        )

        #expect(result.succeeded)

        // Verify upload
        let data = try await client.getObject(bucket: bucket, key: "uploaded.txt")
        #expect(String(data: data, encoding: .utf8) == "config file test")
    }

    @Test func profileOverridesTakePrecedence() async throws {
        let client = CLITestConfig.createClient()
        let bucket = CLITestConfig.uniqueBucketName(prefix: "cfgoverride")
        try await client.createBucket(bucket)
        defer { Task { await cleanupBucketViaCLI(bucket) } }

        // Run with --profile flag (should override config)
        // This uses the existing behavior (not useConfig)
        let result = try await CLIRunner.run("ls", "minio:\(bucket)/")

        #expect(result.succeeded)
    }

    @Test func unknownProfileShowsAvailable() async throws {
        // Create a config file with known profiles
        let configDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ss3-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: configDir) }

        let configFile = configDir.appendingPathComponent("profiles.json")
        let config = """
        {
          "alpha": "https://alpha.example.com",
          "beta": "https://beta.example.com"
        }
        """
        try config.write(to: configFile, atomically: true, encoding: .utf8)

        let result = try await CLIRunner.run(
            arguments: ["ls", "unknown:bucket/"],
            env: ["XDG_CONFIG_HOME": configDir.path],
            useConfig: false  // Don't add --profile, let it fail
        )

        #expect(!result.succeeded)
        #expect(result.stderr.contains("unknown") || result.stdout.contains("unknown"))
        #expect(result.stderr.contains("alpha") || result.stdout.contains("alpha"))
        #expect(result.stderr.contains("beta") || result.stdout.contains("beta"))
    }
}
```

**Step 2: Run integration tests**

Run: `swift test --filter ss3IntegrationTests.ConfigFileIntegrationTests`
Expected: All PASS

**Step 3: Lint and commit**

```bash
swiftlint --fix && swiftlint --strict
git add Tests/ss3IntegrationTests/ConfigFileIntegrationTests.swift
git commit -m "test(cli): add config file integration tests"
```

---

## Task 11: Credential Precedence - Env Vars Override URL

**Files:**
- Modify: `Tests/ss3Tests/ProfileTests.swift`

The current implementation already has env vars as fallback (URL wins). We need to flip this so env vars win.

**Step 1: Write test for new credential precedence**

```swift
// Add to Tests/ss3Tests/ProfileTests.swift
@Test func profileEnvCredentialsOverrideURL() throws {
    let profile = try Profile.parse(name: "e2", url: "https://url-key:url-secret@s3.example.com")
    let env = Environment(getenv: { key in
        switch key {
        case "SS3_E2_ACCESS_KEY": return "env-key"
        case "SS3_E2_SECRET_KEY": return "env-secret"
        default: return nil
        }
    })
    let resolved = try profile.resolve(with: env)

    // Env vars should override URL credentials
    #expect(resolved.accessKeyId == "env-key")
    #expect(resolved.secretAccessKey == "env-secret")
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter ss3Tests.ProfileTests/profileEnvCredentialsOverrideURL`
Expected: FAIL (currently URL credentials win)

**Step 3: Update Profile.resolve to prioritize env vars**

Modify `Sources/ss3/Configuration/Profile.swift`, change the `resolve` method:

```swift
extension Profile {
    func resolve(with env: Environment, pathStyle: Bool = false) throws -> ResolvedProfile {
        let envPrefix = Profile.envVarPrefix(for: name)

        // Environment variables take precedence over URL credentials
        let resolvedAccessKey = env.value(for: "\(envPrefix)_ACCESS_KEY") ?? accessKeyId
        let resolvedSecretKey = env.value(for: "\(envPrefix)_SECRET_KEY") ?? secretAccessKey

        guard let accessKey = resolvedAccessKey, let secretKey = resolvedSecretKey else {
            throw ProfileError.missingCredentials(profile: name)
        }

        return ResolvedProfile(
            name: name,
            endpoint: endpoint,
            region: region,
            bucket: bucket,
            accessKeyId: accessKey,
            secretAccessKey: secretKey,
            pathStyle: pathStyle
        )
    }
}
```

**Step 4: Update existing test that expects old behavior**

The test `profileURLCredentialsTakePrecedence` now has wrong expectations. Rename and fix it:

```swift
@Test func profileURLCredentialsUsedWhenNoEnvVars() throws {
    let profile = try Profile.parse(name: "e2", url: "https://url-key:url-secret@s3.example.com")
    let env = Environment(getenv: { _ in nil })  // No env vars
    let resolved = try profile.resolve(with: env)

    #expect(resolved.accessKeyId == "url-key")
    #expect(resolved.secretAccessKey == "url-secret")
}
```

**Step 5: Run tests to verify they pass**

Run: `swift test --filter ss3Tests.ProfileTests`
Expected: All PASS

**Step 6: Lint and commit**

```bash
swiftlint --fix && swiftlint --strict
git add Sources/ss3/Configuration/Profile.swift Tests/ss3Tests/ProfileTests.swift
git commit -m "feat(config): env vars override URL credentials"
```

---

## Task 12: Run Full Test Suite

**Step 1: Run all tests**

Run: `swift test`
Expected: All 127+ tests pass

**Step 2: Fix any failures**

If any tests fail, investigate and fix.

**Step 3: Final lint check**

```bash
swiftlint --fix && swiftlint --strict
```

**Step 4: Final commit if needed**

```bash
git status
# If there are changes:
git add -A
git commit -m "fix: address test failures"
```

---

## Task 13: Update CLAUDE.md Documentation

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update the ss3 CLI Usage section**

Add documentation about the config file:

```markdown
### Config File

ss3 supports a config file at `$XDG_CONFIG_HOME/ss3/profiles.json` (defaults to `~/.config/ss3/profiles.json`):

```json
{
  "e2": "https://key:secret@bucket.s3.us-west-001.example.com",
  "r2": "https://account.r2.cloudflarestorage.com"
}
```

With a config file, you can use profiles directly without `--profile`:

```bash
ss3 ls e2:mybucket              # Uses profile from config
ss3 cp ./file.txt e2:mybucket/  # Uses profile from config
```

**Precedence (highest to lowest):**
1. `--profile name url` flag overrides config
2. Config file profile lookup
3. Environment variables for credentials override URL credentials
```

**Step 2: Commit documentation**

```bash
git add CLAUDE.md
git commit -m "docs: add config file documentation to CLAUDE.md"
```

---

## Summary

This plan implements config file support in 13 tasks:

1. **ConfigFile - Basic Loading** - Core struct with JSON parsing
2. **ConfigFile - Edge Cases** - Multiple profiles, empty file, malformed JSON
3. **ConfigFile - XDG Path** - Default path resolution with XDG_CONFIG_HOME
4. **ProfileResolver - Core** - Profile lookup logic with error messages
5. **ProfileResolver - No Config** - Handle missing config file
6. **GlobalOptions - Parse Override** - Extract CLI override tuple
7. **ListCommand - Update** - Use config-based resolution
8. **CopyCommand - Update** - Use config-based resolution
9. **CLIRunner - Update** - Support config file in tests
10. **Integration Tests** - Config file end-to-end tests
11. **Credential Precedence** - Env vars override URL credentials
12. **Full Test Suite** - Verify everything works
13. **Documentation** - Update CLAUDE.md

Each task follows TDD: write failing test, implement, verify, commit.
