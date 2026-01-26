# Profile CLI Option Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace legacy S3 configuration options with a single `--profile <name> <url>` option that encodes endpoint, credentials, bucket, and region in a URL.

**Architecture:** Profile URLs are parsed to extract credentials (userinfo), bucket/region (from `.s3.` virtual-host pattern), and endpoint. Credentials can alternatively come from `SS3_<NAME>_ACCESS_KEY` / `SS3_<NAME>_SECRET_KEY` environment variables. Paths use `profile:bucket/key` format instead of `s3://bucket/key`.

**Tech Stack:** Swift 6.2, ArgumentParser, Swift Testing

---

## Task 1: Create Profile Type with URL Parsing

**Files:**
- Create: `Sources/ss3/Configuration/Profile.swift`
- Test: `Tests/ss3Tests/ProfileTests.swift`

**Step 1: Write failing tests for Profile URL parsing**

Create `Tests/ss3Tests/ProfileTests.swift`:

```swift
import Testing
@testable import ss3

@Test func profileParsesSimpleURL() throws {
    let profile = try Profile.parse(name: "e2", url: "https://s3.example.com")
    #expect(profile.name == "e2")
    #expect(profile.endpoint.absoluteString == "https://s3.example.com")
    #expect(profile.region == "auto")
    #expect(profile.bucket == nil)
    #expect(profile.accessKeyId == nil)
    #expect(profile.secretAccessKey == nil)
}

@Test func profileParsesCredentialsFromURL() throws {
    let profile = try Profile.parse(name: "e2", url: "https://keyid:secret@s3.example.com")
    #expect(profile.accessKeyId == "keyid")
    #expect(profile.secretAccessKey == "secret")
    #expect(profile.endpoint.absoluteString == "https://s3.example.com")
}

@Test func profileParsesBucketFromVirtualHost() throws {
    let profile = try Profile.parse(name: "e2", url: "https://mybucket.s3.us-west-2.example.com")
    #expect(profile.bucket == "mybucket")
    #expect(profile.region == "us-west-2")
}

@Test func profileParsesRegionAfterS3Marker() throws {
    let profile = try Profile.parse(name: "e2", url: "https://s3.eu-central-1.amazonaws.com")
    #expect(profile.bucket == nil)
    #expect(profile.region == "eu-central-1")
}

@Test func profileParsesFullURL() throws {
    let profile = try Profile.parse(name: "b2", url: "https://key:secret@mybucket.s3.sjc-003.backblazeb2.com")
    #expect(profile.name == "b2")
    #expect(profile.accessKeyId == "key")
    #expect(profile.secretAccessKey == "secret")
    #expect(profile.bucket == "mybucket")
    #expect(profile.region == "sjc-003")
    #expect(profile.endpoint.absoluteString == "https://mybucket.s3.sjc-003.backblazeb2.com")
}

@Test func profileThrowsForInvalidURL() throws {
    #expect(throws: ProfileError.self) {
        try Profile.parse(name: "e2", url: "not a url")
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter ss3Tests.ProfileTests 2>&1 | head -20`
Expected: Compilation error - Profile type not found

**Step 3: Write Profile implementation**

Create `Sources/ss3/Configuration/Profile.swift`:

```swift
import Foundation

enum ProfileError: Error, CustomStringConvertible {
    case invalidURL(String)
    case missingCredentials(profile: String)

    var description: String {
        switch self {
        case .invalidURL(let url):
            return "Invalid profile URL: \(url)"
        case .missingCredentials(let profile):
            let envPrefix = Profile.envVarPrefix(for: profile)
            return "Missing credentials for profile '\(profile)'. " +
                   "Provide in URL or set \(envPrefix)_ACCESS_KEY and \(envPrefix)_SECRET_KEY"
        }
    }
}

struct Profile: Sendable, Equatable {
    let name: String
    let endpoint: URL
    let region: String
    let bucket: String?
    let accessKeyId: String?
    let secretAccessKey: String?

    static func parse(name: String, url urlString: String) throws -> Profile {
        guard let url = URL(string: urlString) else {
            throw ProfileError.invalidURL(urlString)
        }

        // Extract credentials from userinfo
        let accessKeyId = url.user
        let secretAccessKey = url.password

        // Parse host for bucket and region
        let host = url.host ?? ""
        let (bucket, region) = parseHost(host)

        // Rebuild endpoint URL without credentials
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.user = nil
        components.password = nil
        let endpoint = components.url!

        return Profile(
            name: name,
            endpoint: endpoint,
            region: region,
            bucket: bucket,
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey
        )
    }

    private static func parseHost(_ host: String) -> (bucket: String?, region: String) {
        // Look for .s3. marker in host
        guard let s3Range = host.range(of: ".s3.") else {
            // No .s3. marker - check if host starts with "s3."
            if host.hasPrefix("s3.") {
                let afterS3 = host.dropFirst(3) // drop "s3."
                let region = extractRegion(from: String(afterS3))
                return (nil, region)
            }
            return (nil, "auto")
        }

        // Part before .s3. is the bucket
        let bucket = String(host[..<s3Range.lowerBound])

        // Part after .s3. contains region
        let afterS3 = String(host[s3Range.upperBound...])
        let region = extractRegion(from: afterS3)

        return (bucket.isEmpty ? nil : bucket, region)
    }

    private static func extractRegion(from hostPart: String) -> String {
        // Region is everything up to the next dot (TLD or domain)
        guard let dotIndex = hostPart.firstIndex(of: ".") else {
            return hostPart.isEmpty ? "auto" : hostPart
        }
        let region = String(hostPart[..<dotIndex])
        return region.isEmpty ? "auto" : region
    }

    static func envVarPrefix(for profileName: String) -> String {
        let normalized = profileName
            .uppercased()
            .map { $0.isLetter || $0.isNumber ? $0 : Character("_") }
        return "SS3_\(String(normalized))"
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter ss3Tests.ProfileTests`
Expected: All 6 tests pass

**Step 5: Run swiftlint and fix any issues**

Run: `swiftlint --fix && swiftlint`
Expected: No violations

**Step 6: Commit**

```bash
git add Sources/ss3/Configuration/Profile.swift Tests/ss3Tests/ProfileTests.swift
git commit -m "feat(ss3): add Profile type with URL parsing"
```

---

## Task 2: Add ResolvedProfile and Resolution Logic

**Files:**
- Modify: `Sources/ss3/Configuration/Profile.swift`
- Test: `Tests/ss3Tests/ProfileTests.swift`

**Step 1: Add failing tests for profile resolution**

Append to `Tests/ss3Tests/ProfileTests.swift`:

```swift
@Test func profileResolvesWithURLCredentials() throws {
    let profile = try Profile.parse(name: "e2", url: "https://key:secret@s3.example.com")
    let env = Environment(getenv: { _ in nil })
    let resolved = try profile.resolve(with: env)

    #expect(resolved.accessKeyId == "key")
    #expect(resolved.secretAccessKey == "secret")
}

@Test func profileResolvesWithEnvCredentials() throws {
    let profile = try Profile.parse(name: "e2", url: "https://s3.example.com")
    let env = Environment(getenv: { key in
        switch key {
        case "SS3_E2_ACCESS_KEY": return "env-key"
        case "SS3_E2_SECRET_KEY": return "env-secret"
        default: return nil
        }
    })
    let resolved = try profile.resolve(with: env)

    #expect(resolved.accessKeyId == "env-key")
    #expect(resolved.secretAccessKey == "env-secret")
}

@Test func profileURLCredentialsTakePrecedence() throws {
    let profile = try Profile.parse(name: "e2", url: "https://url-key:url-secret@s3.example.com")
    let env = Environment(getenv: { key in
        switch key {
        case "SS3_E2_ACCESS_KEY": return "env-key"
        case "SS3_E2_SECRET_KEY": return "env-secret"
        default: return nil
        }
    })
    let resolved = try profile.resolve(with: env)

    #expect(resolved.accessKeyId == "url-key")
    #expect(resolved.secretAccessKey == "url-secret")
}

@Test func profileThrowsWhenNoCredentials() throws {
    let profile = try Profile.parse(name: "e2", url: "https://s3.example.com")
    let env = Environment(getenv: { _ in nil })

    #expect(throws: ProfileError.self) {
        try profile.resolve(with: env)
    }
}

@Test func profileEnvVarNormalizesName() {
    #expect(Profile.envVarPrefix(for: "prod-backup") == "SS3_PROD_BACKUP")
    #expect(Profile.envVarPrefix(for: "my.profile") == "SS3_MY_PROFILE")
    #expect(Profile.envVarPrefix(for: "e2") == "SS3_E2")
}
```

**Step 2: Run tests to verify new ones fail**

Run: `swift test --filter ss3Tests.ProfileTests 2>&1 | head -30`
Expected: Compilation error - resolve method not found

**Step 3: Add ResolvedProfile and resolve method**

Add to `Sources/ss3/Configuration/Profile.swift` after the Profile struct:

```swift
struct ResolvedProfile: Sendable {
    let name: String
    let endpoint: URL
    let region: String
    let bucket: String?
    let accessKeyId: String
    let secretAccessKey: String
}

extension Profile {
    func resolve(with env: Environment) throws -> ResolvedProfile {
        let envPrefix = Profile.envVarPrefix(for: name)

        let resolvedAccessKey = accessKeyId ?? env.value(for: "\(envPrefix)_ACCESS_KEY")
        let resolvedSecretKey = secretAccessKey ?? env.value(for: "\(envPrefix)_SECRET_KEY")

        guard let accessKey = resolvedAccessKey, let secretKey = resolvedSecretKey else {
            throw ProfileError.missingCredentials(profile: name)
        }

        return ResolvedProfile(
            name: name,
            endpoint: endpoint,
            region: region,
            bucket: bucket,
            accessKeyId: accessKey,
            secretAccessKey: secretKey
        )
    }
}
```

**Step 4: Update Environment to support dynamic key lookup**

Modify `Sources/ss3/Configuration/Environment.swift`:

```swift
import Foundation

struct Environment: Sendable {
    private let getenv: @Sendable (String) -> String?

    init(getenv: @Sendable @escaping (String) -> String? = { ProcessInfo.processInfo.environment[$0] }) {
        self.getenv = getenv
    }

    func value(for key: String) -> String? {
        getenv(key)
    }
}
```

**Step 5: Run tests to verify they pass**

Run: `swift test --filter ss3Tests.ProfileTests`
Expected: All 11 tests pass

**Step 6: Run swiftlint and fix any issues**

Run: `swiftlint --fix && swiftlint`
Expected: No violations

**Step 7: Commit**

```bash
git add Sources/ss3/Configuration/Profile.swift Sources/ss3/Configuration/Environment.swift
git commit -m "feat(ss3): add ResolvedProfile with env var fallback"
```

---

## Task 3: Update S3Path for Profile-Based Paths

**Files:**
- Modify: `Sources/ss3/Configuration/S3Path.swift`
- Modify: `Tests/ss3Tests/S3PathTests.swift`

**Step 1: Write failing tests for new path format**

Replace contents of `Tests/ss3Tests/S3PathTests.swift`:

```swift
import Testing
@testable import ss3

// Local path tests
@Test func s3PathParsesAbsoluteLocal() {
    let path = S3Path.parse("/home/user/file.txt")
    #expect(path == .local("/home/user/file.txt"))
}

@Test func s3PathParsesRelativeLocal() {
    let path = S3Path.parse("./file.txt")
    #expect(path == .local("./file.txt"))
}

@Test func s3PathParsesParentRelativeLocal() {
    let path = S3Path.parse("../file.txt")
    #expect(path == .local("../file.txt"))
}

@Test func s3PathParsesSimpleFilenameAsLocal() {
    // No colon = local path
    let path = S3Path.parse("file.txt")
    #expect(path == .local("file.txt"))
}

// Remote path tests - profile:bucket/key format
@Test func s3PathParsesProfileListBuckets() {
    // e2: or e2:/ or e2:. all mean list buckets
    #expect(S3Path.parse("e2:") == .remote(profile: "e2", bucket: nil, key: nil))
    #expect(S3Path.parse("e2:/") == .remote(profile: "e2", bucket: nil, key: nil))
    #expect(S3Path.parse("e2:.") == .remote(profile: "e2", bucket: nil, key: nil))
}

@Test func s3PathParsesProfileBucketOnly() {
    let path = S3Path.parse("e2:mybucket")
    #expect(path == .remote(profile: "e2", bucket: "mybucket", key: nil))
}

@Test func s3PathParsesProfileBucketWithTrailingSlash() {
    let path = S3Path.parse("e2:mybucket/")
    #expect(path == .remote(profile: "e2", bucket: "mybucket", key: nil))
}

@Test func s3PathParsesProfileBucketAndKey() {
    let path = S3Path.parse("e2:mybucket/path/to/file.txt")
    #expect(path == .remote(profile: "e2", bucket: "mybucket", key: "path/to/file.txt"))
}

@Test func s3PathParsesProfileBucketAndKeyWithSlash() {
    let path = S3Path.parse("e2:mybucket/dir/")
    #expect(path == .remote(profile: "e2", bucket: "mybucket", key: "dir/"))
}

// Convenience properties
@Test func s3PathIsLocal() {
    #expect(S3Path.local("/file.txt").isLocal)
    #expect(S3Path.local("file.txt").isLocal)
    #expect(!S3Path.remote(profile: "e2", bucket: "b", key: "k").isLocal)
}

@Test func s3PathIsRemote() {
    #expect(!S3Path.local("/file.txt").isRemote)
    #expect(S3Path.remote(profile: "e2", bucket: "b", key: "k").isRemote)
}

@Test func s3PathProfileName() {
    #expect(S3Path.local("/file.txt").profile == nil)
    #expect(S3Path.remote(profile: "e2", bucket: "b", key: "k").profile == "e2")
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter ss3Tests.S3PathTests 2>&1 | head -20`
Expected: Compilation error - remote case doesn't match

**Step 3: Rewrite S3Path**

Replace contents of `Sources/ss3/Configuration/S3Path.swift`:

```swift
enum S3Path: Equatable, Sendable {
    case local(String)
    case remote(profile: String, bucket: String?, key: String?)

    var isLocal: Bool {
        if case .local = self { return true }
        return false
    }

    var isRemote: Bool {
        if case .remote = self { return true }
        return false
    }

    var profile: String? {
        if case .remote(let profile, _, _) = self { return profile }
        return nil
    }

    static func parse(_ path: String) -> S3Path {
        // Colon is the discriminator - if present, it's a profile path
        guard let colonIndex = path.firstIndex(of: ":") else {
            // No colon = local path
            return .local(path)
        }

        let profile = String(path[..<colonIndex])
        let remainder = String(path[path.index(after: colonIndex)...])

        // Handle list buckets cases: "e2:" or "e2:/" or "e2:."
        if remainder.isEmpty || remainder == "/" || remainder == "." {
            return .remote(profile: profile, bucket: nil, key: nil)
        }

        // Parse bucket/key from remainder
        let components = remainder.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let bucket = String(components[0])

        if components.count == 1 {
            // Just bucket, no slash after
            return .remote(profile: profile, bucket: bucket, key: nil)
        }

        // Has slash - check what's after
        let keyPart = String(components[1])
        if keyPart.isEmpty {
            // Trailing slash only: "e2:bucket/"
            return .remote(profile: profile, bucket: bucket, key: nil)
        }

        return .remote(profile: profile, bucket: bucket, key: keyPart)
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter ss3Tests.S3PathTests`
Expected: All 12 tests pass

**Step 5: Run swiftlint and fix any issues**

Run: `swiftlint --fix && swiftlint`
Expected: No violations

**Step 6: Commit**

```bash
git add Sources/ss3/Configuration/S3Path.swift Tests/ss3Tests/S3PathTests.swift
git commit -m "feat(ss3): update S3Path for profile:bucket/key format"
```

---

## Task 4: Update GlobalOptions for --profile

**Files:**
- Modify: `Sources/ss3/Configuration/GlobalOptions.swift`
- Modify: `Tests/ss3Tests/GlobalOptionsTests.swift`

**Step 1: Write failing tests for new GlobalOptions**

Replace contents of `Tests/ss3Tests/GlobalOptionsTests.swift`:

```swift
import Testing
import ArgumentParser
@testable import ss3

@Test func globalOptionsParsesProfile() throws {
    let options = try GlobalOptions.parse(["--profile", "e2", "https://s3.example.com"])

    #expect(options.profileArgs == ["e2", "https://s3.example.com"])
}

@Test func globalOptionsRequiresTwoProfileArgs() throws {
    // Missing URL
    #expect(throws: (any Error).self) {
        let options = try GlobalOptions.parse(["--profile", "e2"])
        _ = try options.parseProfile()
    }
}

@Test func globalOptionsParseProfileReturnsProfile() throws {
    let options = try GlobalOptions.parse(["--profile", "e2", "https://key:secret@s3.example.com"])
    let profile = try options.parseProfile()

    #expect(profile.name == "e2")
    #expect(profile.accessKeyId == "key")
}

@Test func globalOptionsFormatDefault() throws {
    let options = try GlobalOptions.parse(["--profile", "e2", "https://s3.example.com"])
    #expect(options.format == .human)
}

@Test func globalOptionsFormatJson() throws {
    let options = try GlobalOptions.parse(["--profile", "e2", "https://s3.example.com", "--format", "json"])
    #expect(options.format == .json)
}

@Test func globalOptionsVerbose() throws {
    let options = try GlobalOptions.parse(["--profile", "e2", "https://s3.example.com", "--verbose"])
    #expect(options.verbose == true)
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter ss3Tests.GlobalOptionsTests 2>&1 | head -20`
Expected: Compilation error - profileArgs not found

**Step 3: Rewrite GlobalOptions**

Replace contents of `Sources/ss3/Configuration/GlobalOptions.swift`:

```swift
import ArgumentParser

struct GlobalOptions: ParsableArguments {
    @Option(name: .long, parsing: .upToNextOption, help: "Profile: <name> <url>")
    var profileArgs: [String] = []

    @Flag(help: "Verbose error output")
    var verbose: Bool = false

    @Option(help: "Output format (human, json, tsv)")
    var format: OutputFormat = .human

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
Expected: All 6 tests pass

**Step 5: Run swiftlint and fix any issues**

Run: `swiftlint --fix && swiftlint`
Expected: No violations

**Step 6: Commit**

```bash
git add Sources/ss3/Configuration/GlobalOptions.swift Tests/ss3Tests/GlobalOptionsTests.swift
git commit -m "feat(ss3): update GlobalOptions for --profile option"
```

---

## Task 5: Update ClientFactory for ResolvedProfile

**Files:**
- Modify: `Sources/ss3/Configuration/ClientFactory.swift`

**Step 1: Rewrite ClientFactory**

Replace contents of `Sources/ss3/Configuration/ClientFactory.swift`:

```swift
import Foundation
import SwiftS3

enum ClientFactory {
    static func createClient(from profile: ResolvedProfile) -> S3Client {
        let config = S3Configuration(
            accessKeyId: profile.accessKeyId,
            secretAccessKey: profile.secretAccessKey,
            region: profile.region,
            endpoint: profile.endpoint
        )
        return S3Client(configuration: config)
    }
}
```

**Step 2: Build to verify compilation**

Run: `swift build 2>&1 | tail -20`
Expected: Compilation errors in ListCommand and CopyCommand (expected - they still use old API)

**Step 3: Commit ClientFactory change**

```bash
git add Sources/ss3/Configuration/ClientFactory.swift
git commit -m "refactor(ss3): update ClientFactory for ResolvedProfile"
```

---

## Task 6: Update ListCommand

**Files:**
- Modify: `Sources/ss3/Commands/ListCommand.swift`

**Step 1: Rewrite ListCommand**

Replace contents of `Sources/ss3/Commands/ListCommand.swift`:

```swift
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
```

**Step 2: Build to verify ListCommand compiles**

Run: `swift build 2>&1 | grep -E "(error|warning)" | head -10`
Expected: Errors only in CopyCommand

**Step 3: Commit**

```bash
git add Sources/ss3/Commands/ListCommand.swift
git commit -m "feat(ss3): update ListCommand for --profile option"
```

---

## Task 7: Update CopyCommand with Directory Detection

**Files:**
- Modify: `Sources/ss3/Commands/CopyCommand.swift`

**Step 1: Rewrite CopyCommand**

Replace contents of `Sources/ss3/Commands/CopyCommand.swift`:

```swift
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
        let profile = try options.parseProfile()
        let env = Environment()
        let resolved = try profile.resolve(with: env)
        let formatter = options.format.createFormatter()

        let sourcePath = S3Path.parse(source)
        let destPath = S3Path.parse(destination)

        guard sourcePath.isLocal != destPath.isLocal else {
            throw ValidationError("Must specify exactly one local and one remote path")
        }

        // Validate remote path uses correct profile
        if let remoteProfile = sourcePath.profile ?? destPath.profile {
            guard remoteProfile == profile.name else {
                throw ValidationError("Path profile '\(remoteProfile)' doesn't match --profile '\(profile.name)'")
            }
        }

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

        let data = try Data(contentsOf: fileURL)

        if data.count > multipartThreshold {
            let uploader = MultipartUploader(client: client, chunkSize: chunkSize, maxParallel: parallel)
            try await uploader.upload(bucket: bucket, key: key, fileURL: fileURL, fileSize: Int64(data.count))
        } else {
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

**Step 2: Build to verify everything compiles**

Run: `swift build`
Expected: Build succeeded

**Step 3: Run all tests**

Run: `swift test`
Expected: All tests pass

**Step 4: Run swiftlint**

Run: `swiftlint --fix && swiftlint`
Expected: No violations

**Step 5: Commit**

```bash
git add Sources/ss3/Commands/CopyCommand.swift
git commit -m "feat(ss3): update CopyCommand for --profile with directory detection"
```

---

## Task 8: Update Environment Tests

**Files:**
- Modify: `Tests/ss3Tests/EnvironmentTests.swift`

**Step 1: Update tests for new Environment API**

Replace contents of `Tests/ss3Tests/EnvironmentTests.swift`:

```swift
import Testing
@testable import ss3

@Test func environmentReadsValue() {
    let env = Environment(getenv: { key in
        if key == "SS3_E2_ACCESS_KEY" { return "test-key" }
        return nil
    })
    #expect(env.value(for: "SS3_E2_ACCESS_KEY") == "test-key")
}

@Test func environmentReturnsNilForMissing() {
    let env = Environment(getenv: { _ in nil })
    #expect(env.value(for: "SS3_E2_ACCESS_KEY") == nil)
}

@Test func environmentUsesProvidedGetenv() {
    var calledWith: [String] = []
    let env = Environment(getenv: { key in
        calledWith.append(key)
        return "value"
    })
    _ = env.value(for: "TEST_KEY")
    #expect(calledWith == ["TEST_KEY"])
}
```

**Step 2: Run tests**

Run: `swift test --filter ss3Tests.EnvironmentTests`
Expected: All 3 tests pass

**Step 3: Commit**

```bash
git add Tests/ss3Tests/EnvironmentTests.swift
git commit -m "test(ss3): update Environment tests for new API"
```

---

## Task 9: Clean Up Unused Code and Update Documentation

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Run all tests to ensure everything works**

Run: `swift test`
Expected: All tests pass

**Step 2: Run swiftlint on entire project**

Run: `swiftlint`
Expected: No violations

**Step 3: Update CLAUDE.md usage section**

Find and replace the "ss3 CLI Usage" section in `CLAUDE.md` with:

```markdown
## ss3 CLI Usage

### Profile Option

```bash
ss3 --profile <name> <url> COMMAND [OPTIONS]
```

**Profile URL format:**
- Credentials in URL: `https://accessKey:secretKey@s3.example.com`
- Virtual-host bucket/region: `https://mybucket.s3.us-west-2.example.com`
- Simple endpoint: `https://s3.example.com` (region defaults to "auto")

**Environment variables for credentials:**
- `SS3_<NAME>_ACCESS_KEY`: Access key for profile `<NAME>`
- `SS3_<NAME>_SECRET_KEY`: Secret key for profile `<NAME>`
- Profile name is uppercased, non-alphanumeric chars become underscores

**Output formats:** human (default), json, tsv

### Path Format

Paths use `profile:bucket/key` format:
- `e2:` or `e2:/` - list buckets
- `e2:mybucket` - list bucket root
- `e2:mybucket/prefix` - list with prefix
- `e2:mybucket/path/file.txt` - specific object

Local paths have no colon: `./file.txt`, `/path/to/file`, `file.txt`

### Commands

**List buckets:**
```bash
ss3 --profile e2 https://key:secret@s3.example.com ls e2:
ss3 --profile e2 https://s3.example.com ls e2: --format json
```

**List objects in bucket:**
```bash
ss3 --profile e2 https://s3.example.com ls e2:mybucket/prefix
```

**Copy local file to S3:**
```bash
ss3 --profile e2 https://s3.example.com cp ./file.txt e2:mybucket/dir/
```

**Download from S3:**
```bash
SS3_E2_ACCESS_KEY=xxx SS3_E2_SECRET_KEY=yyy \
ss3 --profile e2 https://s3.example.com cp e2:mybucket/file.txt ./local.txt
```
```

**Step 4: Commit documentation update**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for --profile CLI option"
```

---

## Task 10: Final Verification

**Step 1: Run full test suite**

Run: `swift test`
Expected: All tests pass

**Step 2: Build release**

Run: `swift build -c release`
Expected: Build succeeded

**Step 3: Test CLI manually (optional if minio available)**

```bash
.build/release/ss3 --profile test https://minioadmin:minioadmin@localhost:9199 ls test:
```

**Step 4: Create final summary commit if needed**

Review git log:
```bash
git log --oneline -10
```

All implementation is complete.
