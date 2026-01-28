# ls Options Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `-l`/`-h` (long format) and `-t` (time sort) options to `ss3 ls`, remove JSON/TSV output formats.

**Architecture:** Replace the generic `OutputFormatter` protocol with a simpler `ListFormatter` that handles short/long format based on flags. Sorting logic lives in `ListCommand`. Remove `--format` global option.

**Tech Stack:** Swift 6.2, ArgumentParser, Swift Testing

---

## Task 1: Add Compact Size Formatter

Unit tests for the new compact size format (`1.2M`, `99.9K`, etc).

**Files:**
- Modify: `Tests/ss3Tests/HumanFormatterTests.swift`
- Modify: `Sources/ss3/Output/HumanFormatter.swift`

**Step 1: Write failing tests for compact size format**

Add to `Tests/ss3Tests/HumanFormatterTests.swift`:

```swift
@Test func compactSizeFormatsBytes() {
    let formatter = HumanFormatter()

    #expect(formatter.formatCompactSize(0) == "   0B")
    #expect(formatter.formatCompactSize(1) == "   1B")
    #expect(formatter.formatCompactSize(999) == " 999B")
}

@Test func compactSizeFormatsKilobytes() {
    let formatter = HumanFormatter()

    #expect(formatter.formatCompactSize(1024) == " 1.0K")
    #expect(formatter.formatCompactSize(1536) == " 1.5K")
    #expect(formatter.formatCompactSize(10240) == "10.0K")
    #expect(formatter.formatCompactSize(102400) == " 100K")
}

@Test func compactSizeFormatsMegabytes() {
    let formatter = HumanFormatter()

    #expect(formatter.formatCompactSize(1048576) == " 1.0M")
    #expect(formatter.formatCompactSize(104857600) == " 100M")
}

@Test func compactSizeFormatsLargeValues() {
    let formatter = HumanFormatter()

    #expect(formatter.formatCompactSize(1073741824) == " 1.0G")
    #expect(formatter.formatCompactSize(1099511627776) == " 1.0T")
}
```

**Step 2: Run tests to verify they fail**

Run: `cd /home/sprite/swift-s3/.worktrees/ls-options && swift test --filter ss3Tests.HumanFormatterTests 2>&1 | head -30`
Expected: Compilation error - `formatCompactSize` not found

**Step 3: Implement formatCompactSize**

Add to `Sources/ss3/Output/HumanFormatter.swift` (after existing `formatSize` method):

```swift
func formatCompactSize(_ bytes: Int64) -> String {
    let units = ["B", "K", "M", "G", "T"]
    var value = Double(bytes)
    var unitIndex = 0

    while value >= 1024 && unitIndex < units.count - 1 {
        value /= 1024
        unitIndex += 1
    }

    let unit = units[unitIndex]

    if unitIndex == 0 {
        // Bytes: no decimal, right-align to 5 chars
        return String(format: "%4dB", Int(value))
    } else if value >= 100 {
        // 100+ in unit: no decimal (e.g., "100K", "999M")
        return String(format: "%4d%@", Int(value), unit)
    } else {
        // Under 100: one decimal (e.g., "1.0K", "99.9M")
        return String(format: "%4.1f%@", value, unit)
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `cd /home/sprite/swift-s3/.worktrees/ls-options && swift test --filter ss3Tests.HumanFormatterTests`
Expected: All tests pass

**Step 5: Lint and commit**

```bash
cd /home/sprite/swift-s3/.worktrees/ls-options && swiftlint --fix && swiftlint --strict
git add Tests/ss3Tests/HumanFormatterTests.swift Sources/ss3/Output/HumanFormatter.swift
git commit -m "feat(ls): add compact size formatter for -l option"
```

---

## Task 2: Add Unix ls-Style Date Formatter

Unit tests for Unix-style date formatting (`Jan 28 14:30` vs `Jan 28  2024`).

**Files:**
- Modify: `Tests/ss3Tests/HumanFormatterTests.swift`
- Modify: `Sources/ss3/Output/HumanFormatter.swift`

**Step 1: Write failing tests for Unix date format**

Add to `Tests/ss3Tests/HumanFormatterTests.swift`:

```swift
@Test func lsDateFormatsRecentDates() {
    let formatter = HumanFormatter()

    // Date from 1 month ago should show time
    let oneMonthAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
    let result = formatter.formatLsDate(oneMonthAgo)

    // Should be like "Dec 28 14:30" - 12 chars, contains time
    #expect(result.count == 12)
    #expect(result.contains(":"))  // Has time separator
}

@Test func lsDateFormatsOldDates() {
    let formatter = HumanFormatter()

    // Date from 8 months ago should show year
    let eightMonthsAgo = Date().addingTimeInterval(-240 * 24 * 60 * 60)
    let result = formatter.formatLsDate(eightMonthsAgo)

    // Should be like "May 28  2025" - 12 chars, contains year
    #expect(result.count == 12)
    #expect(!result.contains(":"))  // No time
    #expect(result.contains("202"))  // Has year
}

@Test func lsDateEdgeCaseExactlySixMonths() {
    let formatter = HumanFormatter()

    // Exactly 6 months ago should show year (>= 6 months threshold)
    let sixMonthsAgo = Date().addingTimeInterval(-182 * 24 * 60 * 60)
    let result = formatter.formatLsDate(sixMonthsAgo)

    #expect(result.count == 12)
    #expect(!result.contains(":"))  // Should show year, not time
}
```

**Step 2: Run tests to verify they fail**

Run: `cd /home/sprite/swift-s3/.worktrees/ls-options && swift test --filter ss3Tests.HumanFormatterTests 2>&1 | head -30`
Expected: Compilation error - `formatLsDate` not found

**Step 3: Implement formatLsDate**

Add to `Sources/ss3/Output/HumanFormatter.swift`:

```swift
func formatLsDate(_ date: Date) -> String {
    let now = Date()
    let sixMonthsAgo = now.addingTimeInterval(-182 * 24 * 60 * 60)

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")

    if date >= sixMonthsAgo {
        // Recent: "Jan 28 14:30"
        formatter.dateFormat = "MMM dd HH:mm"
    } else {
        // Old: "Jan 28  2024" (two spaces before year)
        formatter.dateFormat = "MMM dd  yyyy"
    }

    return formatter.string(from: date)
}
```

**Step 4: Run tests to verify they pass**

Run: `cd /home/sprite/swift-s3/.worktrees/ls-options && swift test --filter ss3Tests.HumanFormatterTests`
Expected: All tests pass

**Step 5: Lint and commit**

```bash
cd /home/sprite/swift-s3/.worktrees/ls-options && swiftlint --fix && swiftlint --strict
git add Tests/ss3Tests/HumanFormatterTests.swift Sources/ss3/Output/HumanFormatter.swift
git commit -m "feat(ls): add Unix ls-style date formatter"
```

---

## Task 3: Add ListFormatter for Short/Long Output

New formatter specifically for `ls` command with short/long modes.

**Files:**
- Create: `Sources/ss3/Output/ListFormatter.swift`
- Create: `Tests/ss3Tests/ListFormatterTests.swift`

**Step 1: Write failing tests for ListFormatter**

Create `Tests/ss3Tests/ListFormatterTests.swift`:

```swift
import Testing
import Foundation
@testable import ss3
import SwiftS3

@Test func shortFormatObjectsShowsNamesOnly() {
    let formatter = ListFormatter(longFormat: false, sortByTime: false)
    let objects = [
        S3Object(key: "file1.txt", lastModified: nil, etag: nil, size: 1024, storageClass: nil, owner: nil),
        S3Object(key: "file2.txt", lastModified: nil, etag: nil, size: 2048, storageClass: nil, owner: nil)
    ]

    let result = formatter.formatObjects(objects, prefixes: ["folder/"])
    let lines = result.split(separator: "\n").map(String.init)

    #expect(lines.count == 3)
    #expect(lines[0] == "file1.txt")
    #expect(lines[1] == "file2.txt")
    #expect(lines[2] == "folder/")
}

@Test func longFormatObjectsShowsSizeDateName() {
    let formatter = ListFormatter(longFormat: true, sortByTime: false)
    let date = Date(timeIntervalSince1970: 1706400000)  // Fixed date for testing
    let objects = [
        S3Object(key: "file.txt", lastModified: date, etag: nil, size: 1536, storageClass: nil, owner: nil)
    ]

    let result = formatter.formatObjects(objects, prefixes: [])

    #expect(result.contains(" 1.5K"))  // Compact size
    #expect(result.contains("file.txt"))
}

@Test func longFormatDirectoriesShowNamesOnly() {
    let formatter = ListFormatter(longFormat: true, sortByTime: false)
    let objects: [S3Object] = []

    let result = formatter.formatObjects(objects, prefixes: ["docs/", "images/"])
    let lines = result.split(separator: "\n").map(String.init)

    #expect(lines.count == 2)
    #expect(lines[0] == "docs/")
    #expect(lines[1] == "images/")
}

@Test func sortByTimeOrdersFilesFirst() {
    let formatter = ListFormatter(longFormat: false, sortByTime: true)
    let older = Date(timeIntervalSince1970: 1000000)
    let newer = Date(timeIntervalSince1970: 2000000)
    let objects = [
        S3Object(key: "older.txt", lastModified: older, etag: nil, size: 100, storageClass: nil, owner: nil),
        S3Object(key: "newer.txt", lastModified: newer, etag: nil, size: 100, storageClass: nil, owner: nil)
    ]

    let result = formatter.formatObjects(objects, prefixes: ["zfolder/", "afolder/"])
    let lines = result.split(separator: "\n").map(String.init)

    // Files sorted by time (newer first), then dirs alphabetically
    #expect(lines[0] == "newer.txt")
    #expect(lines[1] == "older.txt")
    #expect(lines[2] == "afolder/")
    #expect(lines[3] == "zfolder/")
}

@Test func shortFormatBucketsShowsNamesOnly() {
    let formatter = ListFormatter(longFormat: false, sortByTime: false)
    let buckets = [
        Bucket(name: "bucket1", creationDate: nil, region: nil),
        Bucket(name: "bucket2", creationDate: nil, region: nil)
    ]

    let result = formatter.formatBuckets(buckets)
    let lines = result.split(separator: "\n").map(String.init)

    #expect(lines.count == 2)
    #expect(lines[0] == "bucket1")
    #expect(lines[1] == "bucket2")
}

@Test func longFormatBucketsShowsDateName() {
    let formatter = ListFormatter(longFormat: true, sortByTime: false)
    let date = Date(timeIntervalSince1970: 1706400000)
    let buckets = [
        Bucket(name: "mybucket", creationDate: date, region: nil)
    ]

    let result = formatter.formatBuckets(buckets)

    #expect(result.contains("mybucket"))
    // Should have date but no size column
}

@Test func sortByTimeSortsBucketsByCreation() {
    let formatter = ListFormatter(longFormat: false, sortByTime: true)
    let older = Date(timeIntervalSince1970: 1000000)
    let newer = Date(timeIntervalSince1970: 2000000)
    let buckets = [
        Bucket(name: "older-bucket", creationDate: older, region: nil),
        Bucket(name: "newer-bucket", creationDate: newer, region: nil)
    ]

    let result = formatter.formatBuckets(buckets)
    let lines = result.split(separator: "\n").map(String.init)

    #expect(lines[0] == "newer-bucket")
    #expect(lines[1] == "older-bucket")
}
```

**Step 2: Run tests to verify they fail**

Run: `cd /home/sprite/swift-s3/.worktrees/ls-options && swift test --filter ss3Tests.ListFormatterTests 2>&1 | head -30`
Expected: Compilation error - `ListFormatter` not found

**Step 3: Implement ListFormatter**

Create `Sources/ss3/Output/ListFormatter.swift`:

```swift
import Foundation
import SwiftS3

struct ListFormatter: Sendable {
    let longFormat: Bool
    let sortByTime: Bool

    private let humanFormatter = HumanFormatter()

    func formatObjects(_ objects: [S3Object], prefixes: [String]) -> String {
        var lines: [String] = []

        // Sort objects
        let sortedObjects: [S3Object]
        if sortByTime {
            sortedObjects = objects.sorted { obj1, obj2 in
                let date1 = obj1.lastModified ?? Date.distantPast
                let date2 = obj2.lastModified ?? Date.distantPast
                return date1 > date2  // Most recent first
            }
        } else {
            sortedObjects = objects.sorted { $0.key < $1.key }
        }

        // Format objects (files first when sorting by time)
        for object in sortedObjects {
            if longFormat {
                let size = object.size.map { humanFormatter.formatCompactSize($0) } ?? "    -"
                let date = object.lastModified.map { humanFormatter.formatLsDate($0) } ?? "            "
                lines.append("\(size)  \(date)  \(object.key)")
            } else {
                lines.append(object.key)
            }
        }

        // Sort and add prefixes (directories) at the end
        let sortedPrefixes = prefixes.sorted()
        for prefix in sortedPrefixes {
            lines.append(prefix)
        }

        return lines.joined(separator: "\n")
    }

    func formatBuckets(_ buckets: [Bucket]) -> String {
        var lines: [String] = []

        let sortedBuckets: [Bucket]
        if sortByTime {
            sortedBuckets = buckets.sorted { b1, b2 in
                let date1 = b1.creationDate ?? Date.distantPast
                let date2 = b2.creationDate ?? Date.distantPast
                return date1 > date2  // Most recent first
            }
        } else {
            sortedBuckets = buckets.sorted { $0.name < $1.name }
        }

        for bucket in sortedBuckets {
            if longFormat {
                let date = bucket.creationDate.map { humanFormatter.formatLsDate($0) } ?? "            "
                lines.append("\(date)  \(bucket.name)")
            } else {
                lines.append(bucket.name)
            }
        }

        return lines.joined(separator: "\n")
    }

    func formatError(_ error: any Error, verbose: Bool) -> String {
        humanFormatter.formatError(error, verbose: verbose)
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `cd /home/sprite/swift-s3/.worktrees/ls-options && swift test --filter ss3Tests.ListFormatterTests`
Expected: All tests pass

**Step 5: Lint and commit**

```bash
cd /home/sprite/swift-s3/.worktrees/ls-options && swiftlint --fix && swiftlint --strict
git add Sources/ss3/Output/ListFormatter.swift Tests/ss3Tests/ListFormatterTests.swift
git commit -m "feat(ls): add ListFormatter with short/long and time sort modes"
```

---

## Task 4: Add -l, -h, -t Flags to ListCommand

Add the new flags to the `ls` command using ArgumentParser.

**Files:**
- Modify: `Sources/ss3/Commands/ListCommand.swift`

**Step 1: Add flags and update formatter usage**

Replace the contents of `Sources/ss3/Commands/ListCommand.swift`:

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
```

**Step 2: Build to verify compilation**

Run: `cd /home/sprite/swift-s3/.worktrees/ls-options && swift build 2>&1 | tail -10`
Expected: Build succeeds

**Step 3: Lint and commit**

```bash
cd /home/sprite/swift-s3/.worktrees/ls-options && swiftlint --fix && swiftlint --strict
git add Sources/ss3/Commands/ListCommand.swift
git commit -m "feat(ls): add -l, -h, -t flags using ListFormatter"
```

---

## Task 5: Remove --format Option and JSON/TSV Formatters

Remove the deprecated output format machinery.

**Files:**
- Modify: `Sources/ss3/Configuration/GlobalOptions.swift`
- Delete: `Sources/ss3/Output/OutputFormat.swift`
- Delete: `Sources/ss3/Output/JSONFormatter.swift`
- Delete: `Sources/ss3/Output/TSVFormatter.swift`
- Delete: `Tests/ss3Tests/OutputFormatTests.swift`
- Delete: `Tests/ss3Tests/OutputFormatFactoryTests.swift`
- Delete: `Tests/ss3Tests/JSONFormatterTests.swift`
- Delete: `Tests/ss3Tests/TSVFormatterTests.swift`

**Step 1: Remove --format from GlobalOptions**

Modify `Sources/ss3/Configuration/GlobalOptions.swift` to remove the format option:

```swift
import ArgumentParser

struct GlobalOptions: ParsableArguments {
    @Option(name: .customLong("profile"), parsing: .upToNextOption, help: "Profile: <name> <url>")
    var profileArgs: [String] = []

    @Flag(name: .long, help: "Use path-style addressing (required for minio/local endpoints)")
    var pathStyle: Bool = false

    @Flag(help: "Verbose error output")
    var verbose: Bool = false

    func parseProfile() throws -> Profile {
        guard profileArgs.count >= 2 else {
            throw ValidationError("--profile requires two arguments: <name> <url>")
        }
        return try Profile.parse(name: profileArgs[0], url: profileArgs[1])
    }

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
}
```

**Step 2: Delete unused files**

```bash
cd /home/sprite/swift-s3/.worktrees/ls-options
rm Sources/ss3/Output/OutputFormat.swift
rm Sources/ss3/Output/JSONFormatter.swift
rm Sources/ss3/Output/TSVFormatter.swift
rm Tests/ss3Tests/OutputFormatTests.swift
rm Tests/ss3Tests/OutputFormatFactoryTests.swift
rm Tests/ss3Tests/JSONFormatterTests.swift
rm Tests/ss3Tests/TSVFormatterTests.swift
```

**Step 3: Build to verify compilation**

Run: `cd /home/sprite/swift-s3/.worktrees/ls-options && swift build 2>&1 | tail -10`
Expected: Build succeeds

**Step 4: Run unit tests**

Run: `cd /home/sprite/swift-s3/.worktrees/ls-options && swift test --filter ss3Tests`
Expected: All tests pass

**Step 5: Lint and commit**

```bash
cd /home/sprite/swift-s3/.worktrees/ls-options && swiftlint --fix && swiftlint --strict
git add -A
git commit -m "refactor(ls): remove --format option and JSON/TSV formatters"
```

---

## Task 6: Update Integration Tests

Update integration tests to use new output format and remove JSON/TSV tests.

**Files:**
- Modify: `Tests/ss3IntegrationTests/ListTests.swift`

**Step 1: Update ListTests.swift**

Replace contents of `Tests/ss3IntegrationTests/ListTests.swift`:

```swift
import Testing
import Foundation
import SwiftS3

@Suite("ss3 ls Command", .serialized)
struct ListTests {
    init() async throws {
        try await MinioTestServer.shared.ensureRunning()
    }

    @Test func listBucketsDefault() async throws {
        try await withTestBucket(prefix: "lsbucket") { _, bucket in
            let result = try await CLIRunner.run("ls")

            #expect(result.succeeded)
            #expect(result.stdout.contains(bucket))
            // Default format: just bucket names, no summary line
        }
    }

    @Test func listBucketsLongFormat() async throws {
        try await withTestBucket(prefix: "lslong") { _, bucket in
            let result = try await CLIRunner.run("ls", "-l")

            #expect(result.succeeded)
            #expect(result.stdout.contains(bucket))
            // Long format shows date before bucket name
        }
    }

    @Test func listBucketsHumanFlag() async throws {
        try await withTestBucket(prefix: "lshuman") { _, bucket in
            let result = try await CLIRunner.run("ls", "-h")

            #expect(result.succeeded)
            #expect(result.stdout.contains(bucket))
            // -h is synonym for -l
        }
    }

    @Test func listObjectsDefault() async throws {
        try await withTestBucket(prefix: "lsobj") { client, bucket in
            _ = try await client.putObject(bucket: bucket, key: "file1.txt", data: Data("content1".utf8))
            _ = try await client.putObject(bucket: bucket, key: "file2.txt", data: Data("content2".utf8))

            let result = try await CLIRunner.run("ls", "minio:\(bucket)/")

            #expect(result.succeeded)
            let lines = result.stdout.split(separator: "\n").map(String.init)
            // Default: just filenames, one per line
            #expect(lines.contains("file1.txt"))
            #expect(lines.contains("file2.txt"))
        }
    }

    @Test func listObjectsLongFormat() async throws {
        try await withTestBucket(prefix: "lsobjlong") { client, bucket in
            _ = try await client.putObject(bucket: bucket, key: "test.txt", data: Data("test content".utf8))

            let result = try await CLIRunner.run("ls", "-l", "minio:\(bucket)/")

            #expect(result.succeeded)
            #expect(result.stdout.contains("test.txt"))
            // Long format includes size
            #expect(result.stdout.contains("B") || result.stdout.contains("K"))
        }
    }

    @Test func listObjectsWithPrefix() async throws {
        try await withTestBucket(prefix: "lsprefix") { client, bucket in
            _ = try await client.putObject(bucket: bucket, key: "docs/readme.txt", data: Data("readme".utf8))
            _ = try await client.putObject(bucket: bucket, key: "docs/guide.txt", data: Data("guide".utf8))
            _ = try await client.putObject(bucket: bucket, key: "images/logo.png", data: Data("logo".utf8))

            let result = try await CLIRunner.run("ls", "minio:\(bucket)/docs/")

            #expect(result.succeeded)
            #expect(result.stdout.contains("readme.txt"))
            #expect(result.stdout.contains("guide.txt"))
            #expect(!result.stdout.contains("logo.png"))
        }
    }

    @Test func listObjectsShowsFolders() async throws {
        try await withTestBucket(prefix: "lsfolder") { client, bucket in
            _ = try await client.putObject(bucket: bucket, key: "folder1/file.txt", data: Data("f1".utf8))
            _ = try await client.putObject(bucket: bucket, key: "folder2/file.txt", data: Data("f2".utf8))

            let result = try await CLIRunner.run("ls", "minio:\(bucket)/")

            #expect(result.succeeded)
            #expect(result.stdout.contains("folder1/"))
            #expect(result.stdout.contains("folder2/"))
        }
    }

    @Test func listObjectsSortByTime() async throws {
        try await withTestBucket(prefix: "lstime") { client, bucket in
            // Upload files with slight delay to ensure different timestamps
            _ = try await client.putObject(bucket: bucket, key: "older.txt", data: Data("old".utf8))
            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
            _ = try await client.putObject(bucket: bucket, key: "newer.txt", data: Data("new".utf8))

            let result = try await CLIRunner.run("ls", "-t", "minio:\(bucket)/")

            #expect(result.succeeded)
            let lines = result.stdout.split(separator: "\n").map(String.init)
            // Most recent first
            let newerIndex = lines.firstIndex(of: "newer.txt")
            let olderIndex = lines.firstIndex(of: "older.txt")
            #expect(newerIndex != nil && olderIndex != nil)
            #expect(newerIndex! < olderIndex!)
        }
    }

    @Test func listObjectsCombinedFlags() async throws {
        try await withTestBucket(prefix: "lscombined") { client, bucket in
            _ = try await client.putObject(bucket: bucket, key: "file.txt", data: Data("content".utf8))

            let result = try await CLIRunner.run("ls", "-lt", "minio:\(bucket)/")

            #expect(result.succeeded)
            #expect(result.stdout.contains("file.txt"))
            // Should have size in output (long format)
            #expect(result.stdout.contains("B") || result.stdout.contains("K"))
        }
    }

    @Test func listNonexistentBucketFails() async throws {
        let result = try await CLIRunner.run("ls", "minio:nonexistent-bucket-xyz123/")

        #expect(!result.succeeded)
        #expect(result.exitCode == 1)
    }
}
```

**Step 2: Run integration tests**

Run: `cd /home/sprite/swift-s3/.worktrees/ls-options && swift test --filter ss3IntegrationTests.ListTests`
Expected: All tests pass

**Step 3: Lint and commit**

```bash
cd /home/sprite/swift-s3/.worktrees/ls-options && swiftlint --fix && swiftlint --strict
git add Tests/ss3IntegrationTests/ListTests.swift
git commit -m "test(ls): update integration tests for new -l/-h/-t flags"
```

---

## Task 7: Clean Up Unused OutputFormatter Protocol

The OutputFormatter protocol and HumanFormatter's protocol conformance are no longer needed.

**Files:**
- Delete: `Sources/ss3/Output/OutputFormatter.swift`
- Modify: `Sources/ss3/Output/HumanFormatter.swift` (remove protocol conformance)

**Step 1: Delete OutputFormatter.swift**

```bash
cd /home/sprite/swift-s3/.worktrees/ls-options
rm Sources/ss3/Output/OutputFormatter.swift
```

**Step 2: Clean up HumanFormatter**

Modify `Sources/ss3/Output/HumanFormatter.swift` to remove protocol conformance and unused methods. Keep only the helper methods used by ListFormatter:

```swift
import Foundation
import SwiftS3

struct HumanFormatter: Sendable {
    func formatCompactSize(_ bytes: Int64) -> String {
        let units = ["B", "K", "M", "G", "T"]
        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        let unit = units[unitIndex]

        if unitIndex == 0 {
            return String(format: "%4dB", Int(value))
        } else if value >= 100 {
            return String(format: "%4d%@", Int(value), unit)
        } else {
            return String(format: "%4.1f%@", value, unit)
        }
    }

    func formatLsDate(_ date: Date) -> String {
        let now = Date()
        let sixMonthsAgo = now.addingTimeInterval(-182 * 24 * 60 * 60)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if date >= sixMonthsAgo {
            formatter.dateFormat = "MMM dd HH:mm"
        } else {
            formatter.dateFormat = "MMM dd  yyyy"
        }

        return formatter.string(from: date)
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

**Step 3: Update HumanFormatterTests to match new API**

Modify `Tests/ss3Tests/HumanFormatterTests.swift` to remove tests for removed methods:

```swift
import Testing
import Foundation
@testable import ss3
import SwiftS3

@Test func compactSizeFormatsBytes() {
    let formatter = HumanFormatter()

    #expect(formatter.formatCompactSize(0) == "   0B")
    #expect(formatter.formatCompactSize(1) == "   1B")
    #expect(formatter.formatCompactSize(999) == " 999B")
}

@Test func compactSizeFormatsKilobytes() {
    let formatter = HumanFormatter()

    #expect(formatter.formatCompactSize(1024) == " 1.0K")
    #expect(formatter.formatCompactSize(1536) == " 1.5K")
    #expect(formatter.formatCompactSize(10240) == "10.0K")
    #expect(formatter.formatCompactSize(102400) == " 100K")
}

@Test func compactSizeFormatsMegabytes() {
    let formatter = HumanFormatter()

    #expect(formatter.formatCompactSize(1048576) == " 1.0M")
    #expect(formatter.formatCompactSize(104857600) == " 100M")
}

@Test func compactSizeFormatsLargeValues() {
    let formatter = HumanFormatter()

    #expect(formatter.formatCompactSize(1073741824) == " 1.0G")
    #expect(formatter.formatCompactSize(1099511627776) == " 1.0T")
}

@Test func lsDateFormatsRecentDates() {
    let formatter = HumanFormatter()

    let oneMonthAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
    let result = formatter.formatLsDate(oneMonthAgo)

    #expect(result.count == 12)
    #expect(result.contains(":"))
}

@Test func lsDateFormatsOldDates() {
    let formatter = HumanFormatter()

    let eightMonthsAgo = Date().addingTimeInterval(-240 * 24 * 60 * 60)
    let result = formatter.formatLsDate(eightMonthsAgo)

    #expect(result.count == 12)
    #expect(!result.contains(":"))
    #expect(result.contains("202"))
}

@Test func lsDateEdgeCaseExactlySixMonths() {
    let formatter = HumanFormatter()

    let sixMonthsAgo = Date().addingTimeInterval(-182 * 24 * 60 * 60)
    let result = formatter.formatLsDate(sixMonthsAgo)

    #expect(result.count == 12)
    #expect(!result.contains(":"))
}

@Test func formatErrorShowsMessage() {
    let formatter = HumanFormatter()
    let error = S3APIError(
        code: .accessDenied,
        message: "Access denied",
        resource: nil,
        requestId: nil
    )

    let result = formatter.formatError(error, verbose: false)

    #expect(result.contains("Access denied"))
    #expect(result.contains("Hint:"))
}
```

**Step 4: Build and test**

Run: `cd /home/sprite/swift-s3/.worktrees/ls-options && swift build && swift test --filter ss3Tests`
Expected: Build succeeds, all tests pass

**Step 5: Lint and commit**

```bash
cd /home/sprite/swift-s3/.worktrees/ls-options && swiftlint --fix && swiftlint --strict
git add -A
git commit -m "refactor: remove OutputFormatter protocol, simplify HumanFormatter"
```

---

## Task 8: Run Full Test Suite and Final Verification

Verify everything works together.

**Files:** None (verification only)

**Step 1: Run all unit tests**

Run: `cd /home/sprite/swift-s3/.worktrees/ls-options && swift test --filter SwiftS3Tests && swift test --filter ss3Tests`
Expected: All tests pass

**Step 2: Run all integration tests**

Run: `cd /home/sprite/swift-s3/.worktrees/ls-options && swift test --filter IntegrationTests && swift test --filter ss3IntegrationTests`
Expected: All tests pass

**Step 3: Manual CLI verification**

```bash
cd /home/sprite/swift-s3/.worktrees/ls-options
swift build

# Test help output shows new flags
.build/debug/ss3 ls --help
```

Expected: Help shows `-l`, `-h`, `-t` flags, no `--format` option

**Step 4: Final lint check**

```bash
cd /home/sprite/swift-s3/.worktrees/ls-options && swiftlint --strict
```

Expected: No violations

---

## Summary

After completing all tasks:
- `ss3 ls` shows names only by default
- `ss3 ls -l` or `ss3 ls -h` shows long format (size, date, name)
- `ss3 ls -t` sorts by modification time
- `ss3 ls -lt` combines both
- Directories always show name only, listed after files when sorting
- JSON and TSV output removed
- All tests passing
