# rm, mv, touch CLI Commands Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add three new CLI commands (`rm`, `mv`, `touch`) for remote object operations.

**Architecture:** Each command is a separate `AsyncParsableCommand` following the existing pattern from `ListCommand.swift` and `CopyCommand.swift`. Commands use `S3Path.parse()` for path validation, `ProfileResolver` for profile resolution, and `S3Client` for S3 operations.

**Tech Stack:** Swift 6.2, ArgumentParser, SwiftS3 library, Swift Testing framework.

---

## Task 1: RemoveCommand Implementation

**Files:**
- Create: `Sources/ss3/Commands/RemoveCommand.swift`
- Modify: `Sources/ss3/SS3.swift` (add to subcommands)

**Step 1: Create RemoveCommand.swift**

```swift
import ArgumentParser
import Foundation
import SwiftS3

struct RemoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rm",
        abstract: "Remove a remote file"
    )

    @OptionGroup var options: GlobalOptions

    @Argument(help: "Remote path to delete (profile:bucket/key)")
    var path: String

    func run() async throws {
        let env = Environment()
        let formatter = options.format.createFormatter()
        let config = try ConfigFile.loadDefault(env: env)

        // Parse and validate path
        let parsed = S3Path.parse(path)
        guard case .remote(let profileName, let bucket, let key) = parsed else {
            throw ValidationError("Path must be remote: profile:bucket/key")
        }
        guard let bucket = bucket else {
            throw ValidationError("Path must include bucket: profile:bucket/key")
        }
        guard let key = key else {
            throw ValidationError("Path must include key: profile:bucket/key")
        }
        guard !key.hasSuffix("/") else {
            throw ValidationError("Cannot delete directories. Path must not end with /")
        }

        // Resolve profile and create client
        let resolver = ProfileResolver(config: config)
        let profile = try resolver.resolve(
            profileName: profileName,
            cliOverride: options.parseProfileOverride()
        )
        let resolved = try profile.resolve(with: env, pathStyle: options.pathStyle)
        let client = ClientFactory.createClient(from: resolved)

        do {
            try await client.deleteObject(bucket: bucket, key: key)
            print(formatter.formatSuccess("Deleted \(bucket)/\(key)"))
        } catch {
            printError(formatter.formatError(error, verbose: options.verbose))
            throw ExitCode(1)
        }
    }
}
```

**Step 2: Add to SS3.swift subcommands**

Edit `Sources/ss3/SS3.swift` to add `RemoveCommand.self` to the subcommands array:

```swift
subcommands: [ListCommand.self, CopyCommand.self, RemoveCommand.self],
```

**Step 3: Verify it compiles**

Run: `swift build`
Expected: Build succeeds

**Step 4: Run swiftlint**

Run: `swiftlint --fix && swiftlint --strict`
Expected: No violations

**Step 5: Commit**

```bash
git add Sources/ss3/Commands/RemoveCommand.swift Sources/ss3/SS3.swift
git commit -m "feat(ss3): add rm command for deleting remote files"
```

---

## Task 2: RemoveCommand Unit Tests

**Files:**
- Create: `Tests/ss3Tests/RemoveCommandTests.swift`

**Step 1: Create RemoveCommandTests.swift**

Note: We can't directly unit test command execution without mocking. Instead, we test the S3Path validation logic that the command relies on. The path validation is already covered in `S3PathTests.swift`, so we add edge case tests specific to rm requirements.

```swift
import Testing
@testable import ss3

@Test func s3PathRejectsDirectoryPath() {
    let path = S3Path.parse("e2:mybucket/dir/")
    guard case .remote(_, _, let key) = path else {
        Issue.record("Expected remote path")
        return
    }
    // rm command should reject paths ending with /
    #expect(key?.hasSuffix("/") == true)
}

@Test func s3PathRequiresKeyForRemove() {
    let bucketOnly = S3Path.parse("e2:mybucket")
    guard case .remote(_, let bucket, let key) = bucketOnly else {
        Issue.record("Expected remote path")
        return
    }
    #expect(bucket == "mybucket")
    #expect(key == nil)  // rm requires key to be non-nil
}

@Test func s3PathParsesValidRemoveTarget() {
    let path = S3Path.parse("e2:mybucket/path/to/file.txt")
    guard case .remote(let profile, let bucket, let key) = path else {
        Issue.record("Expected remote path")
        return
    }
    #expect(profile == "e2")
    #expect(bucket == "mybucket")
    #expect(key == "path/to/file.txt")
    #expect(key?.hasSuffix("/") == false)
}
```

**Step 2: Run tests to verify they pass**

Run: `swift test --filter ss3Tests`
Expected: All tests pass

**Step 3: Run swiftlint**

Run: `swiftlint --fix && swiftlint --strict`
Expected: No violations

**Step 4: Commit**

```bash
git add Tests/ss3Tests/RemoveCommandTests.swift
git commit -m "test(ss3): add unit tests for rm command path validation"
```

---

## Task 3: RemoveCommand Integration Tests

**Files:**
- Create: `Tests/ss3IntegrationTests/RemoveTests.swift`

**Step 1: Create RemoveTests.swift**

```swift
import Testing
import Foundation
import SwiftS3

@Suite("ss3 rm Command", .serialized)
struct RemoveTests {
    init() async throws {
        try await MinioTestServer.shared.ensureRunning()
    }

    @Test("Remove existing file succeeds")
    func removeExistingFile() async throws {
        try await withTestBucket(prefix: "rmok") { client, bucket in
            // Create a file via library
            let content = "File to delete"
            _ = try await client.putObject(bucket: bucket, key: "delete-me.txt", data: Data(content.utf8))

            // Delete via CLI
            let result = try await CLIRunner.run("rm", "minio:\(bucket)/delete-me.txt")

            #expect(result.succeeded)
            #expect(result.stdout.contains("Deleted"))

            // Verify file is gone
            do {
                _ = try await client.headObject(bucket: bucket, key: "delete-me.txt")
                Issue.record("Expected file to be deleted")
            } catch {
                // Expected - file should not exist
            }
        }
    }

    @Test("Remove nonexistent file fails")
    func removeNonexistentFile() async throws {
        try await withTestBucket(prefix: "rmfail") { _, bucket in
            let result = try await CLIRunner.run("rm", "minio:\(bucket)/nonexistent.txt")

            #expect(!result.succeeded)
            #expect(result.exitCode == 1)
        }
    }

    @Test("Remove directory path fails")
    func removeDirectoryPathFails() async throws {
        try await withTestBucket(prefix: "rmdir") { _, bucket in
            // Path ending with / should be rejected by validation
            let result = try await CLIRunner.run("rm", "minio:\(bucket)/somedir/")

            #expect(!result.succeeded)
            // ArgumentParser's ValidationError exits with code 64
            #expect(result.exitCode == 64)
        }
    }

    @Test("Remove without key fails")
    func removeWithoutKeyFails() async throws {
        try await withTestBucket(prefix: "rmnokey") { _, bucket in
            // Just bucket, no key
            let result = try await CLIRunner.run("rm", "minio:\(bucket)")

            #expect(!result.succeeded)
            #expect(result.exitCode == 64)
        }
    }

    @Test("Remove local path fails")
    func removeLocalPathFails() async throws {
        let result = try await CLIRunner.run("rm", "/tmp/somefile.txt")

        #expect(!result.succeeded)
        #expect(result.exitCode == 64)
    }

    @Test("Remove nested key succeeds")
    func removeNestedKey() async throws {
        try await withTestBucket(prefix: "rmnest") { client, bucket in
            // Create nested file
            _ = try await client.putObject(
                bucket: bucket,
                key: "deep/nested/path/file.txt",
                data: Data("nested content".utf8)
            )

            // Delete via CLI
            let result = try await CLIRunner.run("rm", "minio:\(bucket)/deep/nested/path/file.txt")

            #expect(result.succeeded)
        }
    }
}
```

**Step 2: Run integration tests**

Run: `swift test --filter ss3IntegrationTests.RemoveTests`
Expected: All tests pass

**Step 3: Run swiftlint**

Run: `swiftlint --fix && swiftlint --strict`
Expected: No violations

**Step 4: Commit**

```bash
git add Tests/ss3IntegrationTests/RemoveTests.swift
git commit -m "test(ss3): add integration tests for rm command"
```

---

## Task 4: TouchCommand Implementation

**Files:**
- Create: `Sources/ss3/Commands/TouchCommand.swift`
- Modify: `Sources/ss3/SS3.swift` (add to subcommands)

**Step 1: Create TouchCommand.swift**

```swift
import ArgumentParser
import Foundation
import SwiftS3

struct TouchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "touch",
        abstract: "Create an empty remote file"
    )

    @OptionGroup var options: GlobalOptions

    @Argument(help: "Remote path to create (profile:bucket/key)")
    var path: String

    func run() async throws {
        let env = Environment()
        let formatter = options.format.createFormatter()
        let config = try ConfigFile.loadDefault(env: env)

        // Parse and validate path
        let parsed = S3Path.parse(path)
        guard case .remote(let profileName, let bucket, let key) = parsed else {
            throw ValidationError("Path must be remote: profile:bucket/key")
        }
        guard let bucket = bucket else {
            throw ValidationError("Path must include bucket: profile:bucket/key")
        }
        guard let key = key else {
            throw ValidationError("Path must include key: profile:bucket/key")
        }
        guard !key.hasSuffix("/") else {
            throw ValidationError("Cannot create directory. Path must not end with /")
        }

        // Resolve profile and create client
        let resolver = ProfileResolver(config: config)
        let profile = try resolver.resolve(
            profileName: profileName,
            cliOverride: options.parseProfileOverride()
        )
        let resolved = try profile.resolve(with: env, pathStyle: options.pathStyle)
        let client = ClientFactory.createClient(from: resolved)

        do {
            // Check if file already exists
            do {
                _ = try await client.headObject(bucket: bucket, key: key)
                // File exists - error
                throw ValidationError("File already exists: \(bucket)/\(key)")
            } catch let error as S3APIError where error.code == .noSuchKey {
                // File doesn't exist - good, proceed
            }

            // Create empty file
            _ = try await client.putObject(bucket: bucket, key: key, data: Data())
            print(formatter.formatSuccess("Created \(bucket)/\(key)"))
        } catch let error as ValidationError {
            printError(formatter.formatError(error, verbose: options.verbose))
            throw ExitCode(1)
        } catch {
            printError(formatter.formatError(error, verbose: options.verbose))
            throw ExitCode(1)
        }
    }
}
```

**Step 2: Add to SS3.swift subcommands**

Edit `Sources/ss3/SS3.swift`:

```swift
subcommands: [ListCommand.self, CopyCommand.self, RemoveCommand.self, TouchCommand.self],
```

**Step 3: Verify it compiles**

Run: `swift build`
Expected: Build succeeds

**Step 4: Run swiftlint**

Run: `swiftlint --fix && swiftlint --strict`
Expected: No violations

**Step 5: Commit**

```bash
git add Sources/ss3/Commands/TouchCommand.swift Sources/ss3/SS3.swift
git commit -m "feat(ss3): add touch command for creating empty remote files"
```

---

## Task 5: TouchCommand Unit Tests

**Files:**
- Create: `Tests/ss3Tests/TouchCommandTests.swift`

**Step 1: Create TouchCommandTests.swift**

```swift
import Testing
@testable import ss3

@Test func s3PathParsesValidTouchTarget() {
    let path = S3Path.parse("e2:mybucket/newfile.txt")
    guard case .remote(let profile, let bucket, let key) = path else {
        Issue.record("Expected remote path")
        return
    }
    #expect(profile == "e2")
    #expect(bucket == "mybucket")
    #expect(key == "newfile.txt")
    #expect(key?.hasSuffix("/") == false)
}

@Test func s3PathParsesNestedTouchTarget() {
    let path = S3Path.parse("e2:mybucket/deep/nested/file.txt")
    guard case .remote(_, let bucket, let key) = path else {
        Issue.record("Expected remote path")
        return
    }
    #expect(bucket == "mybucket")
    #expect(key == "deep/nested/file.txt")
}
```

**Step 2: Run tests**

Run: `swift test --filter ss3Tests`
Expected: All tests pass

**Step 3: Run swiftlint**

Run: `swiftlint --fix && swiftlint --strict`
Expected: No violations

**Step 4: Commit**

```bash
git add Tests/ss3Tests/TouchCommandTests.swift
git commit -m "test(ss3): add unit tests for touch command path validation"
```

---

## Task 6: TouchCommand Integration Tests

**Files:**
- Create: `Tests/ss3IntegrationTests/TouchTests.swift`

**Step 1: Create TouchTests.swift**

```swift
import Testing
import Foundation
import SwiftS3

@Suite("ss3 touch Command", .serialized)
struct TouchTests {
    init() async throws {
        try await MinioTestServer.shared.ensureRunning()
    }

    @Test("Touch creates empty file")
    func touchCreatesEmptyFile() async throws {
        try await withTestBucket(prefix: "touchok") { client, bucket in
            // Create via CLI
            let result = try await CLIRunner.run("touch", "minio:\(bucket)/newfile.txt")

            #expect(result.succeeded)
            #expect(result.stdout.contains("Created"))

            // Verify file exists and is empty
            let (data, metadata) = try await client.getObject(bucket: bucket, key: "newfile.txt")
            #expect(data.count == 0)
            #expect(metadata.contentLength == 0)
        }
    }

    @Test("Touch existing file fails")
    func touchExistingFileFails() async throws {
        try await withTestBucket(prefix: "touchexist") { client, bucket in
            // Create a file first
            _ = try await client.putObject(bucket: bucket, key: "existing.txt", data: Data("content".utf8))

            // Try to touch it - should fail
            let result = try await CLIRunner.run("touch", "minio:\(bucket)/existing.txt")

            #expect(!result.succeeded)
            #expect(result.exitCode == 1)
            #expect(result.stderr.contains("already exists"))
        }
    }

    @Test("Touch directory path fails")
    func touchDirectoryPathFails() async throws {
        try await withTestBucket(prefix: "touchdir") { _, bucket in
            let result = try await CLIRunner.run("touch", "minio:\(bucket)/somedir/")

            #expect(!result.succeeded)
            #expect(result.exitCode == 64)
        }
    }

    @Test("Touch without key fails")
    func touchWithoutKeyFails() async throws {
        try await withTestBucket(prefix: "touchnokey") { _, bucket in
            let result = try await CLIRunner.run("touch", "minio:\(bucket)")

            #expect(!result.succeeded)
            #expect(result.exitCode == 64)
        }
    }

    @Test("Touch local path fails")
    func touchLocalPathFails() async throws {
        let result = try await CLIRunner.run("touch", "/tmp/somefile.txt")

        #expect(!result.succeeded)
        #expect(result.exitCode == 64)
    }

    @Test("Touch nested path creates file")
    func touchNestedPath() async throws {
        try await withTestBucket(prefix: "touchnest") { client, bucket in
            let result = try await CLIRunner.run("touch", "minio:\(bucket)/deep/nested/path/file.txt")

            #expect(result.succeeded)

            // Verify file exists
            let (data, _) = try await client.getObject(bucket: bucket, key: "deep/nested/path/file.txt")
            #expect(data.count == 0)
        }
    }
}
```

**Step 2: Run integration tests**

Run: `swift test --filter ss3IntegrationTests.TouchTests`
Expected: All tests pass

**Step 3: Run swiftlint**

Run: `swiftlint --fix && swiftlint --strict`
Expected: No violations

**Step 4: Commit**

```bash
git add Tests/ss3IntegrationTests/TouchTests.swift
git commit -m "test(ss3): add integration tests for touch command"
```

---

## Task 7: MoveCommand Implementation

**Files:**
- Create: `Sources/ss3/Commands/MoveCommand.swift`
- Modify: `Sources/ss3/SS3.swift` (add to subcommands)

**Step 1: Create MoveCommand.swift**

```swift
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
```

**Step 2: Add to SS3.swift subcommands**

Edit `Sources/ss3/SS3.swift`:

```swift
subcommands: [ListCommand.self, CopyCommand.self, RemoveCommand.self, TouchCommand.self, MoveCommand.self],
```

**Step 3: Verify it compiles**

Run: `swift build`
Expected: Build succeeds

**Step 4: Run swiftlint**

Run: `swiftlint --fix && swiftlint --strict`
Expected: No violations

**Step 5: Commit**

```bash
git add Sources/ss3/Commands/MoveCommand.swift Sources/ss3/SS3.swift
git commit -m "feat(ss3): add mv command for moving/renaming remote files"
```

---

## Task 8: MoveCommand Unit Tests

**Files:**
- Create: `Tests/ss3Tests/MoveCommandTests.swift`

**Step 1: Create MoveCommandTests.swift**

```swift
import Testing
@testable import ss3

@Test func s3PathParsesValidMoveSource() {
    let path = S3Path.parse("e2:mybucket/source.txt")
    guard case .remote(let profile, let bucket, let key) = path else {
        Issue.record("Expected remote path")
        return
    }
    #expect(profile == "e2")
    #expect(bucket == "mybucket")
    #expect(key == "source.txt")
}

@Test func s3PathParsesValidMoveDestination() {
    let path = S3Path.parse("e2:mybucket/dest.txt")
    guard case .remote(let profile, let bucket, let key) = path else {
        Issue.record("Expected remote path")
        return
    }
    #expect(profile == "e2")
    #expect(bucket == "mybucket")
    #expect(key == "dest.txt")
}

@Test func s3PathParsesCrossBucketMove() {
    let src = S3Path.parse("e2:bucket1/file.txt")
    let dst = S3Path.parse("e2:bucket2/file.txt")

    guard case .remote(let srcProfile, let srcBucket, _) = src,
          case .remote(let dstProfile, let dstBucket, _) = dst else {
        Issue.record("Expected remote paths")
        return
    }

    #expect(srcProfile == dstProfile)  // Same profile required
    #expect(srcBucket == "bucket1")
    #expect(dstBucket == "bucket2")
}
```

**Step 2: Run tests**

Run: `swift test --filter ss3Tests`
Expected: All tests pass

**Step 3: Run swiftlint**

Run: `swiftlint --fix && swiftlint --strict`
Expected: No violations

**Step 4: Commit**

```bash
git add Tests/ss3Tests/MoveCommandTests.swift
git commit -m "test(ss3): add unit tests for mv command path validation"
```

---

## Task 9: MoveCommand Integration Tests

**Files:**
- Create: `Tests/ss3IntegrationTests/MoveTests.swift`

**Step 1: Create MoveTests.swift**

```swift
import Testing
import Foundation
import SwiftS3

@Suite("ss3 mv Command", .serialized)
struct MoveTests {
    init() async throws {
        try await MinioTestServer.shared.ensureRunning()
    }

    @Test("Move file within same bucket")
    func moveWithinBucket() async throws {
        try await withTestBucket(prefix: "mvsame") { client, bucket in
            // Create source file
            let content = "Content to move"
            _ = try await client.putObject(bucket: bucket, key: "source.txt", data: Data(content.utf8))

            // Move via CLI
            let result = try await CLIRunner.run(
                "mv",
                "minio:\(bucket)/source.txt",
                "minio:\(bucket)/dest.txt"
            )

            #expect(result.succeeded)
            #expect(result.stdout.contains("Moved"))

            // Verify source is gone
            do {
                _ = try await client.headObject(bucket: bucket, key: "source.txt")
                Issue.record("Source should be deleted")
            } catch {
                // Expected
            }

            // Verify destination exists with correct content
            let (data, _) = try await client.getObject(bucket: bucket, key: "dest.txt")
            #expect(String(data: data, encoding: .utf8) == content)
        }
    }

    @Test("Move file to different bucket")
    func moveToDifferentBucket() async throws {
        let client = CLITestConfig.createClient()
        let srcBucket = CLITestConfig.uniqueBucketName(prefix: "mvsrc")
        let dstBucket = CLITestConfig.uniqueBucketName(prefix: "mvdst")

        try await client.createBucket(srcBucket)
        try await client.createBucket(dstBucket)

        defer {
            Task {
                await cleanupBucket(srcBucket)
                await cleanupBucket(dstBucket)
            }
        }

        // Create source file
        let content = "Cross-bucket move"
        _ = try await client.putObject(bucket: srcBucket, key: "file.txt", data: Data(content.utf8))

        // Move via CLI
        let result = try await CLIRunner.run(
            "mv",
            "minio:\(srcBucket)/file.txt",
            "minio:\(dstBucket)/file.txt"
        )

        #expect(result.succeeded)

        // Verify source is gone
        do {
            _ = try await client.headObject(bucket: srcBucket, key: "file.txt")
            Issue.record("Source should be deleted")
        } catch {
            // Expected
        }

        // Verify destination exists
        let (data, _) = try await client.getObject(bucket: dstBucket, key: "file.txt")
        #expect(String(data: data, encoding: .utf8) == content)
    }

    @Test("Move nonexistent file fails")
    func moveNonexistentFails() async throws {
        try await withTestBucket(prefix: "mvfail") { _, bucket in
            let result = try await CLIRunner.run(
                "mv",
                "minio:\(bucket)/nonexistent.txt",
                "minio:\(bucket)/dest.txt"
            )

            #expect(!result.succeeded)
            #expect(result.exitCode == 1)
        }
    }

    @Test("Move overwrites existing destination")
    func moveOverwritesDestination() async throws {
        try await withTestBucket(prefix: "mvover") { client, bucket in
            // Create source and destination files
            let srcContent = "Source content"
            let dstContent = "Destination content"
            _ = try await client.putObject(bucket: bucket, key: "source.txt", data: Data(srcContent.utf8))
            _ = try await client.putObject(bucket: bucket, key: "dest.txt", data: Data(dstContent.utf8))

            // Move (should overwrite)
            let result = try await CLIRunner.run(
                "mv",
                "minio:\(bucket)/source.txt",
                "minio:\(bucket)/dest.txt"
            )

            #expect(result.succeeded)

            // Verify destination has source content
            let (data, _) = try await client.getObject(bucket: bucket, key: "dest.txt")
            #expect(String(data: data, encoding: .utf8) == srcContent)
        }
    }

    @Test("Move directory path fails")
    func moveDirectoryPathFails() async throws {
        try await withTestBucket(prefix: "mvdir") { _, bucket in
            let result = try await CLIRunner.run(
                "mv",
                "minio:\(bucket)/dir/",
                "minio:\(bucket)/dest/"
            )

            #expect(!result.succeeded)
            #expect(result.exitCode == 64)
        }
    }

    @Test("Move local source fails")
    func moveLocalSourceFails() async throws {
        try await withTestBucket(prefix: "mvlocal") { _, bucket in
            let result = try await CLIRunner.run(
                "mv",
                "/tmp/local.txt",
                "minio:\(bucket)/dest.txt"
            )

            #expect(!result.succeeded)
            #expect(result.exitCode == 64)
        }
    }

    @Test("Move to local destination fails")
    func moveToLocalDestinationFails() async throws {
        try await withTestBucket(prefix: "mvlocal2") { client, bucket in
            _ = try await client.putObject(bucket: bucket, key: "source.txt", data: Data("content".utf8))

            let result = try await CLIRunner.run(
                "mv",
                "minio:\(bucket)/source.txt",
                "/tmp/local.txt"
            )

            #expect(!result.succeeded)
            #expect(result.exitCode == 64)
        }
    }

    @Test("Move nested key succeeds")
    func moveNestedKey() async throws {
        try await withTestBucket(prefix: "mvnest") { client, bucket in
            // Create nested source
            _ = try await client.putObject(
                bucket: bucket,
                key: "deep/nested/source.txt",
                data: Data("nested".utf8)
            )

            // Move to different nested path
            let result = try await CLIRunner.run(
                "mv",
                "minio:\(bucket)/deep/nested/source.txt",
                "minio:\(bucket)/other/path/dest.txt"
            )

            #expect(result.succeeded)

            // Verify move worked
            let (data, _) = try await client.getObject(bucket: bucket, key: "other/path/dest.txt")
            #expect(String(data: data, encoding: .utf8) == "nested")
        }
    }
}
```

**Step 2: Run integration tests**

Run: `swift test --filter ss3IntegrationTests.MoveTests`
Expected: All tests pass

**Step 3: Run swiftlint**

Run: `swiftlint --fix && swiftlint --strict`
Expected: No violations

**Step 4: Commit**

```bash
git add Tests/ss3IntegrationTests/MoveTests.swift
git commit -m "test(ss3): add integration tests for mv command"
```

---

## Task 10: Final Verification

**Step 1: Run all unit tests**

Run: `swift test --filter 'SwiftS3Tests|ss3Tests'`
Expected: All tests pass

**Step 2: Run all integration tests**

Run: `swift test --filter 'IntegrationTests|ss3IntegrationTests'`
Expected: All tests pass

**Step 3: Run swiftlint on entire project**

Run: `swiftlint --strict`
Expected: No violations

**Step 4: Verify all commands work manually**

```bash
# Build
swift build

# Test rm
.build/debug/ss3 --help
.build/debug/ss3 rm --help
.build/debug/ss3 mv --help
.build/debug/ss3 touch --help
```

**Step 5: Create final commit if any cleanup needed**

If all passes, no additional commit needed.
