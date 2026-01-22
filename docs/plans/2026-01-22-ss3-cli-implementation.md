# ss3 CLI Tool Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an `ss3` CLI tool that wraps the SwiftS3 library for interacting with S3-compatible APIs.

**Architecture:** Executable target using swift-argument-parser for CLI parsing. Commands delegate to S3Client for operations. Formatters handle output rendering. MultipartUploader handles parallel chunked uploads via TaskGroup.

**Tech Stack:** Swift 6.2, swift-argument-parser, SwiftS3 library, Swift Testing

---

## Task 1: Update Package.swift

**Files:**
- Modify: `Package.swift`

**Step 1: Add swift-argument-parser dependency**

Edit `Package.swift` to add the argument parser dependency and executable target:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftS3",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "SwiftS3",
            targets: ["SwiftS3"]
        ),
        .executable(
            name: "ss3",
            targets: ["ss3"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "SwiftS3",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "SwiftS3Tests",
            dependencies: ["SwiftS3"]
        ),
        .executableTarget(
            name: "ss3",
            dependencies: [
                "SwiftS3",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "ss3Tests",
            dependencies: ["ss3"]
        )
    ]
)
```

**Step 2: Verify package resolves**

Run: `swift package resolve`
Expected: Dependencies resolve successfully

**Step 3: Commit**

```bash
git add Package.swift
git commit -m "chore: add swift-argument-parser dependency and ss3 executable target"
```

---

## Task 2: Create Entry Point and Root Command

**Files:**
- Create: `Sources/ss3/SS3.swift`

**Step 1: Create directory structure**

Run: `mkdir -p Sources/ss3`

**Step 2: Create root command**

Create `Sources/ss3/SS3.swift`:

```swift
import ArgumentParser

@main
struct SS3: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ss3",
        abstract: "A CLI for S3-compatible storage services",
        version: "0.1.0",
        subcommands: [ListCommand.self, CopyCommand.self],
        defaultSubcommand: nil
    )
}
```

**Step 3: Create placeholder ListCommand**

Create `Sources/ss3/Commands/ListCommand.swift`:

```swift
import ArgumentParser

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ls",
        abstract: "List buckets or objects"
    )

    func run() async throws {
        print("ls command not yet implemented")
    }
}
```

**Step 4: Create placeholder CopyCommand**

Create `Sources/ss3/Commands/CopyCommand.swift`:

```swift
import ArgumentParser

struct CopyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cp",
        abstract: "Copy files to/from S3"
    )

    func run() async throws {
        print("cp command not yet implemented")
    }
}
```

**Step 5: Verify it builds**

Run: `swift build`
Expected: Build succeeds

**Step 6: Verify help works**

Run: `.build/debug/ss3 --help`
Expected: Shows help with ls and cp subcommands

**Step 7: Run swiftlint**

Run: `swiftlint`
Expected: No violations (fix any that appear)

**Step 8: Commit**

```bash
git add Sources/ss3/
git commit -m "feat: add ss3 CLI entry point with placeholder commands"
```

---

## Task 3: Implement OutputFormat Enum

**Files:**
- Create: `Sources/ss3/Output/OutputFormat.swift`
- Create: `Tests/ss3Tests/OutputFormatTests.swift`

**Step 1: Create Output directory**

Run: `mkdir -p Sources/ss3/Output`

**Step 2: Write failing test**

Create `Tests/ss3Tests/OutputFormatTests.swift`:

```swift
import Testing
@testable import ss3

@Test func outputFormatDefaultsToHuman() {
    let format = OutputFormat.human
    #expect(format.rawValue == "human")
}

@Test func outputFormatParsesFromString() {
    #expect(OutputFormat(rawValue: "json") == .json)
    #expect(OutputFormat(rawValue: "tsv") == .tsv)
    #expect(OutputFormat(rawValue: "human") == .human)
    #expect(OutputFormat(rawValue: "invalid") == nil)
}
```

**Step 3: Run test to verify it fails**

Run: `swift test --filter ss3Tests`
Expected: FAIL - module 'ss3' not found or OutputFormat not defined

**Step 4: Implement OutputFormat**

Create `Sources/ss3/Output/OutputFormat.swift`:

```swift
import ArgumentParser

enum OutputFormat: String, ExpressibleByArgument, CaseIterable, Sendable {
    case human
    case json
    case tsv
}
```

**Step 5: Run test to verify it passes**

Run: `swift test --filter ss3Tests`
Expected: PASS

**Step 6: Run swiftlint**

Run: `swiftlint`
Expected: No violations

**Step 7: Commit**

```bash
git add Sources/ss3/Output/ Tests/ss3Tests/
git commit -m "feat: add OutputFormat enum with human/json/tsv options"
```

---

## Task 4: Implement Environment Variable Resolution

**Files:**
- Create: `Sources/ss3/Configuration/Environment.swift`
- Create: `Tests/ss3Tests/EnvironmentTests.swift`

**Step 1: Create Configuration directory**

Run: `mkdir -p Sources/ss3/Configuration`

**Step 2: Write failing test**

Create `Tests/ss3Tests/EnvironmentTests.swift`:

```swift
import Testing
@testable import ss3

@Test func environmentReadsKeyId() {
    let env = Environment(getenv: { key in
        if key == "SS3_KEY_ID" { return "test-key" }
        return nil
    })
    #expect(env.keyId == "test-key")
}

@Test func environmentReadsAllVariables() {
    let env = Environment(getenv: { key in
        switch key {
        case "SS3_KEY_ID": return "key123"
        case "SS3_SECRET_KEY": return "secret456"
        case "SS3_REGION": return "us-west-2"
        case "SS3_ENDPOINT": return "https://s3.example.com"
        case "SS3_BUCKET": return "mybucket"
        default: return nil
        }
    })
    #expect(env.keyId == "key123")
    #expect(env.secretKey == "secret456")
    #expect(env.region == "us-west-2")
    #expect(env.endpoint == "https://s3.example.com")
    #expect(env.bucket == "mybucket")
}

@Test func environmentReturnsNilForMissing() {
    let env = Environment(getenv: { _ in nil })
    #expect(env.keyId == nil)
    #expect(env.secretKey == nil)
}
```

**Step 3: Run test to verify it fails**

Run: `swift test --filter ss3Tests.EnvironmentTests`
Expected: FAIL - Environment not defined

**Step 4: Implement Environment**

Create `Sources/ss3/Configuration/Environment.swift`:

```swift
import Foundation

struct Environment: Sendable {
    let keyId: String?
    let secretKey: String?
    let region: String?
    let endpoint: String?
    let bucket: String?

    init(getenv: @Sendable (String) -> String? = { ProcessInfo.processInfo.environment[$0] }) {
        self.keyId = getenv("SS3_KEY_ID")
        self.secretKey = getenv("SS3_SECRET_KEY")
        self.region = getenv("SS3_REGION")
        self.endpoint = getenv("SS3_ENDPOINT")
        self.bucket = getenv("SS3_BUCKET")
    }
}
```

**Step 5: Run test to verify it passes**

Run: `swift test --filter ss3Tests.EnvironmentTests`
Expected: PASS

**Step 6: Run swiftlint**

Run: `swiftlint`
Expected: No violations

**Step 7: Commit**

```bash
git add Sources/ss3/Configuration/ Tests/ss3Tests/EnvironmentTests.swift
git commit -m "feat: add Environment for SS3_* env var resolution"
```

---

## Task 5: Implement GlobalOptions

**Files:**
- Create: `Sources/ss3/Configuration/GlobalOptions.swift`
- Create: `Tests/ss3Tests/GlobalOptionsTests.swift`

**Step 1: Write failing test**

Create `Tests/ss3Tests/GlobalOptionsTests.swift`:

```swift
import Testing
@testable import ss3

@Test func globalOptionsResolvesFromFlag() {
    var options = GlobalOptions()
    options.keyId = "flag-key"

    let env = Environment(getenv: { _ in "env-key" })
    let resolved = options.resolve(with: env)

    #expect(resolved.keyId == "flag-key")
}

@Test func globalOptionsResolvesFromEnv() {
    let options = GlobalOptions()
    let env = Environment(getenv: { key in
        if key == "SS3_KEY_ID" { return "env-key" }
        return nil
    })
    let resolved = options.resolve(with: env)

    #expect(resolved.keyId == "env-key")
}

@Test func globalOptionsB2SetsEndpoint() {
    var options = GlobalOptions()
    options.b2 = true
    options.region = "us-west-002"

    let env = Environment(getenv: { _ in nil })
    let resolved = options.resolve(with: env)

    #expect(resolved.endpoint == "https://s3.us-west-002.backblazeb2.com")
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter ss3Tests.GlobalOptionsTests`
Expected: FAIL - GlobalOptions not defined

**Step 3: Implement GlobalOptions**

Create `Sources/ss3/Configuration/GlobalOptions.swift`:

```swift
import ArgumentParser

struct GlobalOptions: ParsableArguments {
    @Option(name: [.long, .customShort("u")], help: "Access key ID")
    var keyId: String?

    @Option(name: [.long, .customShort("p")], help: "Secret access key")
    var secretKey: String?

    @Option(help: "AWS region")
    var region: String?

    @Option(help: "S3 endpoint URL")
    var endpoint: String?

    @Option(help: "Bucket name")
    var bucket: String?

    @Flag(help: "Use Backblaze B2 endpoint")
    var b2: Bool = false

    @Flag(help: "Verbose error output")
    var verbose: Bool = false

    @Option(help: "Output format (human, json, tsv)")
    var format: OutputFormat = .human
}

struct ResolvedConfiguration: Sendable {
    let keyId: String?
    let secretKey: String?
    let region: String?
    let endpoint: String?
    let bucket: String?
    let verbose: Bool
    let format: OutputFormat
}

extension GlobalOptions {
    func resolve(with env: Environment) -> ResolvedConfiguration {
        let resolvedRegion = region ?? env.region

        var resolvedEndpoint = endpoint ?? env.endpoint
        if b2, let region = resolvedRegion {
            resolvedEndpoint = "https://s3.\(region).backblazeb2.com"
        }

        return ResolvedConfiguration(
            keyId: keyId ?? env.keyId,
            secretKey: secretKey ?? env.secretKey,
            region: resolvedRegion,
            endpoint: resolvedEndpoint,
            bucket: bucket ?? env.bucket,
            verbose: verbose,
            format: format
        )
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter ss3Tests.GlobalOptionsTests`
Expected: PASS

**Step 5: Run swiftlint**

Run: `swiftlint`
Expected: No violations

**Step 6: Commit**

```bash
git add Sources/ss3/Configuration/GlobalOptions.swift Tests/ss3Tests/GlobalOptionsTests.swift
git commit -m "feat: add GlobalOptions with flag/env resolution and B2 support"
```

---

## Task 6: Implement Path Parsing

**Files:**
- Create: `Sources/ss3/Configuration/S3Path.swift`
- Create: `Tests/ss3Tests/S3PathTests.swift`

**Step 1: Write failing test**

Create `Tests/ss3Tests/S3PathTests.swift`:

```swift
import Testing
@testable import ss3

@Test func s3PathParsesLocalFile() {
    let path = S3Path.parse("/home/user/file.txt")
    #expect(path == .local("/home/user/file.txt"))
}

@Test func s3PathParsesRelativeLocal() {
    let path = S3Path.parse("./file.txt")
    #expect(path == .local("./file.txt"))
}

@Test func s3PathParsesCurrentDirLocal() {
    let path = S3Path.parse("file.txt")
    // Single component without slash is ambiguous - treat as remote bucket
    #expect(path == .remote(bucket: "file.txt", key: nil))
}

@Test func s3PathParsesRemoteBucket() {
    let path = S3Path.parse("mybucket/")
    #expect(path == .remote(bucket: "mybucket", key: nil))
}

@Test func s3PathParsesRemoteKey() {
    let path = S3Path.parse("mybucket/path/to/file.txt")
    #expect(path == .remote(bucket: "mybucket", key: "path/to/file.txt"))
}

@Test func s3PathParsesRemoteWithBucketOption() {
    let path = S3Path.parse("path/to/file.txt", defaultBucket: "mybucket")
    #expect(path == .remote(bucket: "mybucket", key: "path/to/file.txt"))
}

@Test func s3PathIsLocal() {
    #expect(S3Path.local("/file.txt").isLocal)
    #expect(!S3Path.remote(bucket: "b", key: "k").isLocal)
}

@Test func s3PathIsRemote() {
    #expect(!S3Path.local("/file.txt").isRemote)
    #expect(S3Path.remote(bucket: "b", key: "k").isRemote)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter ss3Tests.S3PathTests`
Expected: FAIL - S3Path not defined

**Step 3: Implement S3Path**

Create `Sources/ss3/Configuration/S3Path.swift`:

```swift
enum S3Path: Equatable, Sendable {
    case local(String)
    case remote(bucket: String, key: String?)

    var isLocal: Bool {
        if case .local = self { return true }
        return false
    }

    var isRemote: Bool {
        if case .remote = self { return true }
        return false
    }

    static func parse(_ path: String, defaultBucket: String? = nil) -> S3Path {
        // Absolute paths are always local
        if path.hasPrefix("/") {
            return .local(path)
        }

        // Relative paths starting with ./ or ../ are local
        if path.hasPrefix("./") || path.hasPrefix("../") {
            return .local(path)
        }

        // If we have a default bucket and path doesn't look like bucket/key
        if let bucket = defaultBucket {
            return .remote(bucket: bucket, key: path)
        }

        // Parse as bucket/key
        let components = path.split(separator: "/", maxSplits: 1)
        let bucket = String(components[0])

        if components.count == 1 {
            // Just bucket name, possibly with trailing slash
            return .remote(bucket: bucket, key: nil)
        }

        let key = String(components[1])
        return .remote(bucket: bucket, key: key.isEmpty ? nil : key)
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter ss3Tests.S3PathTests`
Expected: PASS

**Step 5: Run swiftlint**

Run: `swiftlint`
Expected: No violations

**Step 6: Commit**

```bash
git add Sources/ss3/Configuration/S3Path.swift Tests/ss3Tests/S3PathTests.swift
git commit -m "feat: add S3Path for local/remote path parsing"
```

---

## Task 7: Implement OutputFormatter Protocol and HumanFormatter

**Files:**
- Create: `Sources/ss3/Output/OutputFormatter.swift`
- Create: `Sources/ss3/Output/HumanFormatter.swift`
- Create: `Tests/ss3Tests/HumanFormatterTests.swift`

**Step 1: Write failing test**

Create `Tests/ss3Tests/HumanFormatterTests.swift`:

```swift
import Testing
import Foundation
@testable import ss3
import SwiftS3

@Test func humanFormatterFormatsBuckets() {
    let formatter = HumanFormatter()
    let buckets = [
        Bucket(name: "bucket1", creationDate: nil, region: nil),
        Bucket(name: "bucket2", creationDate: nil, region: nil)
    ]

    let output = formatter.formatBuckets(buckets)

    #expect(output.contains("bucket1"))
    #expect(output.contains("bucket2"))
    #expect(output.contains("2 buckets"))
}

@Test func humanFormatterFormatsObjects() {
    let formatter = HumanFormatter()
    let objects = [
        S3Object(
            key: "file.txt",
            lastModified: Date(timeIntervalSince1970: 1705312200),
            etag: nil,
            size: 1234,
            storageClass: nil,
            owner: nil
        )
    ]

    let output = formatter.formatObjects(objects, prefixes: [])

    #expect(output.contains("file.txt"))
    #expect(output.contains("1.2 KB"))
    #expect(output.contains("1 item"))
}

@Test func humanFormatterFormatsPrefixes() {
    let formatter = HumanFormatter()
    let output = formatter.formatObjects([], prefixes: ["logs/", "data/"])

    #expect(output.contains("logs/"))
    #expect(output.contains("data/"))
}

@Test func humanFormatterFormatsSize() {
    let formatter = HumanFormatter()

    #expect(formatter.formatSize(0) == "0 B")
    #expect(formatter.formatSize(512) == "512 B")
    #expect(formatter.formatSize(1024) == "1.0 KB")
    #expect(formatter.formatSize(1536) == "1.5 KB")
    #expect(formatter.formatSize(1048576) == "1.0 MB")
    #expect(formatter.formatSize(1073741824) == "1.0 GB")
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter ss3Tests.HumanFormatterTests`
Expected: FAIL - OutputFormatter/HumanFormatter not defined

**Step 3: Create OutputFormatter protocol**

Create `Sources/ss3/Output/OutputFormatter.swift`:

```swift
import SwiftS3

protocol OutputFormatter: Sendable {
    func formatBuckets(_ buckets: [Bucket]) -> String
    func formatObjects(_ objects: [S3Object], prefixes: [String]) -> String
    func formatError(_ error: any Error, verbose: Bool) -> String
    func formatSuccess(_ message: String) -> String
}
```

**Step 4: Implement HumanFormatter**

Create `Sources/ss3/Output/HumanFormatter.swift`:

```swift
import Foundation
import SwiftS3

struct HumanFormatter: OutputFormatter {
    func formatBuckets(_ buckets: [Bucket]) -> String {
        var lines: [String] = []

        for bucket in buckets {
            var line = bucket.name
            if let date = bucket.creationDate {
                line = "\(formatDate(date))  \(line)"
            }
            lines.append(line)
        }

        let summary = "\(buckets.count) bucket\(buckets.count == 1 ? "" : "s")"
        lines.append(summary)

        return lines.joined(separator: "\n")
    }

    func formatObjects(_ objects: [S3Object], prefixes: [String]) -> String {
        var lines: [String] = []
        var totalSize: Int64 = 0

        for prefix in prefixes.sorted() {
            let line = String(repeating: " ", count: 10) + "  " + String(repeating: " ", count: 16) + "  " + prefix
            lines.append(line)
        }

        for object in objects.sorted(by: { $0.key < $1.key }) {
            let sizeStr = object.size.map { formatSize($0) } ?? ""
            let dateStr = object.lastModified.map { formatDate($0) } ?? ""
            let paddedSize = sizeStr.padding(toLength: 10, withPad: " ", startingAt: 0)
            let paddedDate = dateStr.padding(toLength: 16, withPad: " ", startingAt: 0)
            let line = "\(paddedSize)  \(paddedDate)  \(object.key)"
            lines.append(line)
            totalSize += object.size ?? 0
        }

        let itemCount = objects.count + prefixes.count
        let summary = "\(itemCount) item\(itemCount == 1 ? "" : "s")" +
            (totalSize > 0 ? " (\(formatSize(totalSize)) total)" : "")
        lines.append(summary)

        return lines.joined(separator: "\n")
    }

    func formatError(_ error: any Error, verbose: Bool) -> String {
        if let s3Error = error as? S3APIError {
            var lines = ["Error: \(s3Error.message)"]

            if verbose {
                lines.append("Code: \(s3Error.code.rawValue)")
                if let resource = s3Error.resource {
                    lines.append("Resource: \(resource)")
                }
                if let requestId = s3Error.requestId {
                    lines.append("RequestId: \(requestId)")
                }
            }

            lines.append("Hint: \(hintForError(s3Error.code))")
            return lines.joined(separator: "\n")
        }

        return "Error: \(error.localizedDescription)"
    }

    func formatSuccess(_ message: String) -> String {
        message
    }

    func formatSize(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(Int(value)) \(units[unitIndex])"
        }
        return String(format: "%.1f %@", value, units[unitIndex])
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    private func hintForError(_ code: S3APIError.Code) -> String {
        switch code {
        case .accessDenied:
            return "Check that your credentials have permission for this resource"
        case .noSuchBucket:
            return "The specified bucket does not exist"
        case .noSuchKey:
            return "The specified key does not exist in the bucket"
        case .invalidBucketName:
            return "Bucket names must be 3-63 characters, lowercase, and DNS-compliant"
        default:
            return "Check your request parameters and try again"
        }
    }
}
```

**Step 5: Run test to verify it passes**

Run: `swift test --filter ss3Tests.HumanFormatterTests`
Expected: PASS

**Step 6: Run swiftlint**

Run: `swiftlint`
Expected: No violations

**Step 7: Commit**

```bash
git add Sources/ss3/Output/ Tests/ss3Tests/HumanFormatterTests.swift
git commit -m "feat: add OutputFormatter protocol and HumanFormatter"
```

---

## Task 8: Implement JSONFormatter and TSVFormatter

**Files:**
- Create: `Sources/ss3/Output/JSONFormatter.swift`
- Create: `Sources/ss3/Output/TSVFormatter.swift`
- Create: `Tests/ss3Tests/JSONFormatterTests.swift`
- Create: `Tests/ss3Tests/TSVFormatterTests.swift`

**Step 1: Write failing tests**

Create `Tests/ss3Tests/JSONFormatterTests.swift`:

```swift
import Testing
import Foundation
@testable import ss3
import SwiftS3

@Test func jsonFormatterFormatsBuckets() throws {
    let formatter = JSONFormatter()
    let buckets = [
        Bucket(name: "bucket1", creationDate: nil, region: nil)
    ]

    let output = formatter.formatBuckets(buckets)

    #expect(output.contains("\"name\":\"bucket1\""))
}

@Test func jsonFormatterFormatsObjects() throws {
    let formatter = JSONFormatter()
    let objects = [
        S3Object(
            key: "file.txt",
            lastModified: Date(timeIntervalSince1970: 1705312200),
            etag: nil,
            size: 1234,
            storageClass: nil,
            owner: nil
        )
    ]

    let output = formatter.formatObjects(objects, prefixes: [])

    #expect(output.contains("\"key\":\"file.txt\""))
    #expect(output.contains("\"size\":1234"))
}
```

Create `Tests/ss3Tests/TSVFormatterTests.swift`:

```swift
import Testing
import Foundation
@testable import ss3
import SwiftS3

@Test func tsvFormatterFormatsBuckets() {
    let formatter = TSVFormatter()
    let buckets = [
        Bucket(name: "bucket1", creationDate: nil, region: nil),
        Bucket(name: "bucket2", creationDate: nil, region: nil)
    ]

    let output = formatter.formatBuckets(buckets)
    let lines = output.split(separator: "\n")

    #expect(lines.count == 2)
    #expect(lines[0].contains("bucket1"))
    #expect(lines[1].contains("bucket2"))
}

@Test func tsvFormatterFormatsObjects() {
    let formatter = TSVFormatter()
    let objects = [
        S3Object(
            key: "file.txt",
            lastModified: Date(timeIntervalSince1970: 1705312200),
            etag: nil,
            size: 1234,
            storageClass: nil,
            owner: nil
        )
    ]

    let output = formatter.formatObjects(objects, prefixes: [])

    #expect(output.contains("file.txt\t1234\t"))
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter ss3Tests.JSONFormatterTests`
Run: `swift test --filter ss3Tests.TSVFormatterTests`
Expected: FAIL - Formatters not defined

**Step 3: Implement JSONFormatter**

Create `Sources/ss3/Output/JSONFormatter.swift`:

```swift
import Foundation
import SwiftS3

struct JSONFormatter: OutputFormatter {
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    func formatBuckets(_ buckets: [Bucket]) -> String {
        let items = buckets.map { BucketJSON(name: $0.name, creationDate: $0.creationDate) }
        return encode(items)
    }

    func formatObjects(_ objects: [S3Object], prefixes: [String]) -> String {
        var items: [ObjectJSON] = prefixes.map { ObjectJSON(key: $0, size: nil, lastModified: nil) }
        items += objects.map { ObjectJSON(key: $0.key, size: $0.size, lastModified: $0.lastModified) }
        return encode(items)
    }

    func formatError(_ error: any Error, verbose: Bool) -> String {
        if let s3Error = error as? S3APIError {
            let errorJSON = ErrorJSON(
                error: s3Error.message,
                code: verbose ? s3Error.code.rawValue : nil,
                resource: verbose ? s3Error.resource : nil,
                requestId: verbose ? s3Error.requestId : nil
            )
            return encode(errorJSON)
        }
        return encode(ErrorJSON(error: error.localizedDescription, code: nil, resource: nil, requestId: nil))
    }

    func formatSuccess(_ message: String) -> String {
        encode(["message": message])
    }

    private func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

private struct BucketJSON: Encodable {
    let name: String
    let creationDate: Date?
}

private struct ObjectJSON: Encodable {
    let key: String
    let size: Int64?
    let lastModified: Date?
}

private struct ErrorJSON: Encodable {
    let error: String
    let code: String?
    let resource: String?
    let requestId: String?
}
```

**Step 4: Implement TSVFormatter**

Create `Sources/ss3/Output/TSVFormatter.swift`:

```swift
import Foundation
import SwiftS3

struct TSVFormatter: OutputFormatter {
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()

    func formatBuckets(_ buckets: [Bucket]) -> String {
        buckets.map { bucket in
            let date = bucket.creationDate.map { dateFormatter.string(from: $0) } ?? ""
            return "\(bucket.name)\t\(date)"
        }.joined(separator: "\n")
    }

    func formatObjects(_ objects: [S3Object], prefixes: [String]) -> String {
        var lines = prefixes.map { "\($0)\t0\t" }

        lines += objects.map { object in
            let size = object.size ?? 0
            let date = object.lastModified.map { dateFormatter.string(from: $0) } ?? ""
            return "\(object.key)\t\(size)\t\(date)"
        }

        return lines.joined(separator: "\n")
    }

    func formatError(_ error: any Error, verbose: Bool) -> String {
        if let s3Error = error as? S3APIError {
            if verbose {
                return "ERROR\t\(s3Error.code.rawValue)\t\(s3Error.message)"
            }
            return "ERROR\t\(s3Error.message)"
        }
        return "ERROR\t\(error.localizedDescription)"
    }

    func formatSuccess(_ message: String) -> String {
        "OK\t\(message)"
    }
}
```

**Step 5: Run tests to verify they pass**

Run: `swift test --filter ss3Tests.JSONFormatterTests`
Run: `swift test --filter ss3Tests.TSVFormatterTests`
Expected: PASS

**Step 6: Run swiftlint**

Run: `swiftlint`
Expected: No violations

**Step 7: Commit**

```bash
git add Sources/ss3/Output/ Tests/ss3Tests/JSONFormatterTests.swift Tests/ss3Tests/TSVFormatterTests.swift
git commit -m "feat: add JSONFormatter and TSVFormatter"
```

---

## Task 9: Add Formatter Factory

**Files:**
- Modify: `Sources/ss3/Output/OutputFormat.swift`
- Create: `Tests/ss3Tests/OutputFormatFactoryTests.swift`

**Step 1: Write failing test**

Create `Tests/ss3Tests/OutputFormatFactoryTests.swift`:

```swift
import Testing
@testable import ss3

@Test func outputFormatCreatesHumanFormatter() {
    let formatter = OutputFormat.human.createFormatter()
    #expect(formatter is HumanFormatter)
}

@Test func outputFormatCreatesJSONFormatter() {
    let formatter = OutputFormat.json.createFormatter()
    #expect(formatter is JSONFormatter)
}

@Test func outputFormatCreatesTSVFormatter() {
    let formatter = OutputFormat.tsv.createFormatter()
    #expect(formatter is TSVFormatter)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter ss3Tests.OutputFormatFactoryTests`
Expected: FAIL - createFormatter not defined

**Step 3: Add factory method to OutputFormat**

Modify `Sources/ss3/Output/OutputFormat.swift`:

```swift
import ArgumentParser

enum OutputFormat: String, ExpressibleByArgument, CaseIterable, Sendable {
    case human
    case json
    case tsv

    func createFormatter() -> any OutputFormatter {
        switch self {
        case .human: return HumanFormatter()
        case .json: return JSONFormatter()
        case .tsv: return TSVFormatter()
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter ss3Tests.OutputFormatFactoryTests`
Expected: PASS

**Step 5: Run swiftlint**

Run: `swiftlint`
Expected: No violations

**Step 6: Commit**

```bash
git add Sources/ss3/Output/OutputFormat.swift Tests/ss3Tests/OutputFormatFactoryTests.swift
git commit -m "feat: add formatter factory to OutputFormat enum"
```

---

## Task 10: Implement ListCommand

**Files:**
- Modify: `Sources/ss3/Commands/ListCommand.swift`

**Step 1: Implement ListCommand with full functionality**

Replace `Sources/ss3/Commands/ListCommand.swift`:

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
            print(formatter.formatError(error, verbose: config.verbose), to: &standardError)
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

var standardError = FileHandle.standardError

extension FileHandle: @retroactive TextOutputStream {
    public func write(_ string: String) {
        let data = Data(string.utf8)
        self.write(data)
    }
}
```

**Step 2: Verify it builds**

Run: `swift build`
Expected: Build succeeds

**Step 3: Test help output**

Run: `.build/debug/ss3 ls --help`
Expected: Shows help with options

**Step 4: Run swiftlint**

Run: `swiftlint`
Expected: No violations

**Step 5: Commit**

```bash
git add Sources/ss3/Commands/ListCommand.swift
git commit -m "feat: implement ls command for listing buckets and objects"
```

---

## Task 11: Implement CopyCommand (Simple Upload/Download)

**Files:**
- Modify: `Sources/ss3/Commands/CopyCommand.swift`

**Step 1: Implement CopyCommand**

Replace `Sources/ss3/Commands/CopyCommand.swift`:

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

    @Argument(help: "Source path (local file or bucket/key)")
    var source: String

    @Argument(help: "Destination path (local file or bucket/key)")
    var destination: String

    @Option(help: "Multipart threshold in bytes (default: 100MB)")
    var multipartThreshold: Int64 = 100 * 1024 * 1024

    @Option(help: "Chunk size in bytes (default: 10MB)")
    var chunkSize: Int64 = 10 * 1024 * 1024

    @Option(help: "Max parallel chunk uploads (default: 4)")
    var parallel: Int = 4

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

        let sourcePath = S3Path.parse(source, defaultBucket: config.bucket)
        let destPath = S3Path.parse(destination, defaultBucket: config.bucket)

        // Validate: exactly one local and one remote
        guard sourcePath.isLocal != destPath.isLocal else {
            throw ValidationError("Must specify exactly one local and one remote path")
        }

        let s3Config = S3Configuration(
            accessKeyId: keyId,
            secretAccessKey: secretKey,
            region: region,
            endpoint: endpointURL
        )
        let client = S3Client(configuration: s3Config)

        do {
            if sourcePath.isLocal {
                try await upload(
                    client: client,
                    localPath: sourcePath,
                    remotePath: destPath,
                    config: config,
                    formatter: formatter
                )
            } else {
                try await download(
                    client: client,
                    remotePath: sourcePath,
                    localPath: destPath,
                    config: config,
                    formatter: formatter
                )
            }
        } catch {
            print(formatter.formatError(error, verbose: config.verbose), to: &standardError)
            throw ExitCode(1)
        }
    }

    private func upload(
        client: S3Client,
        localPath: S3Path,
        remotePath: S3Path,
        config: ResolvedConfiguration,
        formatter: any OutputFormatter
    ) async throws {
        guard case .local(let filePath) = localPath else {
            throw ValidationError("Expected local source path")
        }
        guard case .remote(let bucket, let keyOrNil) = remotePath else {
            throw ValidationError("Expected remote destination path")
        }

        let fileURL = URL(fileURLWithPath: filePath)
        let fileName = fileURL.lastPathComponent

        // If key is nil or ends with /, append filename
        let key: String
        if let existingKey = keyOrNil {
            if existingKey.hasSuffix("/") {
                key = existingKey + fileName
            } else {
                key = existingKey
            }
        } else {
            key = fileName
        }

        // Read file
        let data = try Data(contentsOf: fileURL)

        if data.count > multipartThreshold {
            // Use multipart upload
            let uploader = MultipartUploader(
                client: client,
                chunkSize: chunkSize,
                maxParallel: parallel
            )
            try await uploader.upload(
                bucket: bucket,
                key: key,
                fileURL: fileURL,
                fileSize: Int64(data.count)
            )
        } else {
            // Simple upload
            _ = try await client.putObject(bucket: bucket, key: key, data: data)
        }

        print(formatter.formatSuccess("Uploaded \(fileName) to \(bucket)/\(key)"))
    }

    private func download(
        client: S3Client,
        remotePath: S3Path,
        localPath: S3Path,
        config: ResolvedConfiguration,
        formatter: any OutputFormatter
    ) async throws {
        guard case .remote(let bucket, let keyOrNil) = remotePath else {
            throw ValidationError("Expected remote source path")
        }
        guard let key = keyOrNil else {
            throw ValidationError("Remote source must include a key, not just bucket")
        }
        guard case .local(let filePath) = localPath else {
            throw ValidationError("Expected local destination path")
        }

        var destinationURL = URL(fileURLWithPath: filePath)

        // If destination is a directory, append the filename from key
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: filePath, isDirectory: &isDirectory),
           isDirectory.boolValue {
            let fileName = URL(fileURLWithPath: key).lastPathComponent
            destinationURL = destinationURL.appendingPathComponent(fileName)
        }

        _ = try await client.downloadObject(bucket: bucket, key: key, to: destinationURL)

        print(formatter.formatSuccess("Downloaded \(bucket)/\(key) to \(destinationURL.path)"))
    }
}
```

**Step 2: Verify it builds**

Run: `swift build`
Expected: Build succeeds (will fail - need MultipartUploader)

**Step 3: Create placeholder MultipartUploader**

Create `Sources/ss3/Transfer/MultipartUploader.swift`:

```swift
import Foundation
import SwiftS3

struct MultipartUploader: Sendable {
    let client: S3Client
    let chunkSize: Int64
    let maxParallel: Int

    func upload(bucket: String, key: String, fileURL: URL, fileSize: Int64) async throws {
        // Placeholder - will implement in next task
        fatalError("Multipart upload not yet implemented")
    }
}
```

**Step 4: Create Transfer directory and verify build**

Run: `mkdir -p Sources/ss3/Transfer && swift build`
Expected: Build succeeds

**Step 5: Test help output**

Run: `.build/debug/ss3 cp --help`
Expected: Shows help with source, destination, and transfer options

**Step 6: Run swiftlint**

Run: `swiftlint`
Expected: No violations

**Step 7: Commit**

```bash
git add Sources/ss3/Commands/CopyCommand.swift Sources/ss3/Transfer/
git commit -m "feat: implement cp command for upload/download with multipart placeholder"
```

---

## Task 12: Implement MultipartUploader with Parallel Uploads

**Files:**
- Modify: `Sources/ss3/Transfer/MultipartUploader.swift`
- Create: `Tests/ss3Tests/MultipartUploaderTests.swift`

**Step 1: Write failing test**

Create `Tests/ss3Tests/MultipartUploaderTests.swift`:

```swift
import Testing
import Foundation
@testable import ss3

@Test func chunkCalculationForSmallFile() {
    let chunks = MultipartUploader.calculateChunks(fileSize: 1000, chunkSize: 500)
    #expect(chunks.count == 2)
    #expect(chunks[0].partNumber == 1)
    #expect(chunks[0].offset == 0)
    #expect(chunks[0].length == 500)
    #expect(chunks[1].partNumber == 2)
    #expect(chunks[1].offset == 500)
    #expect(chunks[1].length == 500)
}

@Test func chunkCalculationWithRemainder() {
    let chunks = MultipartUploader.calculateChunks(fileSize: 1100, chunkSize: 500)
    #expect(chunks.count == 3)
    #expect(chunks[2].length == 100)
}

@Test func chunkCalculationSingleChunk() {
    let chunks = MultipartUploader.calculateChunks(fileSize: 100, chunkSize: 500)
    #expect(chunks.count == 1)
    #expect(chunks[0].length == 100)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter ss3Tests.MultipartUploaderTests`
Expected: FAIL - calculateChunks not defined

**Step 3: Implement MultipartUploader**

Replace `Sources/ss3/Transfer/MultipartUploader.swift`:

```swift
import Foundation
import SwiftS3

struct ChunkInfo: Sendable {
    let partNumber: Int
    let offset: Int64
    let length: Int64
}

struct MultipartUploader: Sendable {
    let client: S3Client
    let chunkSize: Int64
    let maxParallel: Int

    static func calculateChunks(fileSize: Int64, chunkSize: Int64) -> [ChunkInfo] {
        var chunks: [ChunkInfo] = []
        var offset: Int64 = 0
        var partNumber = 1

        while offset < fileSize {
            let remaining = fileSize - offset
            let length = min(chunkSize, remaining)

            chunks.append(ChunkInfo(
                partNumber: partNumber,
                offset: offset,
                length: length
            ))

            offset += length
            partNumber += 1
        }

        return chunks
    }

    func upload(bucket: String, key: String, fileURL: URL, fileSize: Int64) async throws {
        let upload = try await client.createMultipartUpload(bucket: bucket, key: key)

        do {
            let chunks = Self.calculateChunks(fileSize: fileSize, chunkSize: chunkSize)
            let fileHandle = try FileHandle(forReadingFrom: fileURL)
            defer { try? fileHandle.close() }

            let parts = try await withThrowingTaskGroup(of: CompletedPart.self) { group in
                var pending = chunks.makeIterator()
                var inFlight = 0
                var results: [CompletedPart] = []

                // Seed initial batch
                while inFlight < maxParallel, let chunk = pending.next() {
                    let chunkData = try readChunk(fileHandle: fileHandle, chunk: chunk)
                    group.addTask {
                        try await self.client.uploadPart(
                            bucket: bucket,
                            key: key,
                            uploadId: upload.uploadId,
                            partNumber: chunk.partNumber,
                            data: chunkData
                        )
                    }
                    inFlight += 1
                }

                // Process completions and add more
                for try await part in group {
                    results.append(part)
                    if let chunk = pending.next() {
                        let chunkData = try readChunk(fileHandle: fileHandle, chunk: chunk)
                        group.addTask {
                            try await self.client.uploadPart(
                                bucket: bucket,
                                key: key,
                                uploadId: upload.uploadId,
                                partNumber: chunk.partNumber,
                                data: chunkData
                            )
                        }
                    }
                }

                return results
            }

            _ = try await client.completeMultipartUpload(
                bucket: bucket,
                key: key,
                uploadId: upload.uploadId,
                parts: parts
            )
        } catch {
            try? await client.abortMultipartUpload(
                bucket: bucket,
                key: key,
                uploadId: upload.uploadId
            )
            throw error
        }
    }

    private func readChunk(fileHandle: FileHandle, chunk: ChunkInfo) throws -> Data {
        try fileHandle.seek(toOffset: UInt64(chunk.offset))
        guard let data = try fileHandle.read(upToCount: Int(chunk.length)) else {
            throw MultipartError.readFailed
        }
        return data
    }
}

enum MultipartError: Error, LocalizedError {
    case readFailed

    var errorDescription: String? {
        switch self {
        case .readFailed: return "Failed to read chunk from file"
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter ss3Tests.MultipartUploaderTests`
Expected: PASS

**Step 5: Run full test suite**

Run: `swift test`
Expected: All tests pass

**Step 6: Run swiftlint**

Run: `swiftlint`
Expected: No violations

**Step 7: Commit**

```bash
git add Sources/ss3/Transfer/MultipartUploader.swift Tests/ss3Tests/MultipartUploaderTests.swift
git commit -m "feat: implement parallel multipart uploads with TaskGroup"
```

---

## Task 13: Create Test Directory Structure

**Files:**
- Create: `Tests/ss3Tests/` directory structure

**Step 1: Create test directory**

Run: `mkdir -p Tests/ss3Tests`

**Step 2: Verify tests compile and run**

Run: `swift test`
Expected: All tests pass

**Step 3: Commit**

```bash
git add Tests/ss3Tests/
git commit -m "test: add ss3 CLI test directory structure"
```

---

## Task 14: Final Integration and Polish

**Files:**
- All source files

**Step 1: Run full build**

Run: `swift build`
Expected: Build succeeds

**Step 2: Run full test suite**

Run: `swift test`
Expected: All tests pass

**Step 3: Run swiftlint**

Run: `swiftlint`
Expected: No violations

**Step 4: Test CLI manually**

Run: `.build/debug/ss3 --help`
Run: `.build/debug/ss3 ls --help`
Run: `.build/debug/ss3 cp --help`
Expected: All show appropriate help

**Step 5: Build for Linux (if available)**

Run: `swift build --swift-sdk x86_64-swift-linux-musl` (if SDK installed)
Expected: Build succeeds

**Step 6: Commit any final fixes**

```bash
git add -A
git commit -m "chore: final polish and integration fixes"
```

---

## Summary

| Task | Description |
|------|-------------|
| 1 | Update Package.swift with dependencies and targets |
| 2 | Create entry point and root command |
| 3 | Implement OutputFormat enum |
| 4 | Implement Environment variable resolution |
| 5 | Implement GlobalOptions with flag/env resolution |
| 6 | Implement S3Path parsing |
| 7 | Implement OutputFormatter protocol and HumanFormatter |
| 8 | Implement JSONFormatter and TSVFormatter |
| 9 | Add formatter factory to OutputFormat |
| 10 | Implement ListCommand |
| 11 | Implement CopyCommand (simple upload/download) |
| 12 | Implement MultipartUploader with parallel uploads |
| 13 | Create test directory structure |
| 14 | Final integration and polish |
