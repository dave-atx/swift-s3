# Design: ss3 rm, mv, touch Commands

Addresses issues #19, #20, #21.

## Overview

Add three new CLI commands for remote object operations:

| Command | Usage | Purpose |
|---------|-------|---------|
| `rm` | `ss3 rm profile:bucket/key` | Delete remote file |
| `mv` | `ss3 mv profile:bucket/src profile:bucket/dest` | Move/rename remote file |
| `touch` | `ss3 touch profile:bucket/key` | Create 0-byte remote file |

All commands:
- Work only on remote files (not local)
- Require bucket AND key (not just bucket)
- Reject paths ending with `/` (directories)
- Support `--profile` like existing `ls` and `cp`

## S3 API Mapping

| Command | S3 Operations |
|---------|---------------|
| `rm` | `deleteObject` |
| `mv` | `copyObject` + `deleteObject` |
| `touch` | `headObject` (check exists) + `putObject` (empty data) |

All required S3Client methods already exist.

## Command Structure

Each command follows the existing pattern from `CopyCommand.swift`:

```swift
struct RemoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rm",
        abstract: "Remove a remote file"
    )
    @OptionGroup var options: GlobalOptions
    @Argument(help: "Remote path (profile:bucket/key)")
    var path: String

    func run() async throws {
        // 1. Parse path with S3Path.parse()
        // 2. Validate: remote, has bucket, has key, not directory
        // 3. Load config, resolve profile, create client
        // 4. Execute operation with error handling
    }
}
```

Validation logic is duplicated in each command (~10 lines) to keep commands self-contained.

## Error Handling

```swift
do {
    // operation
} catch {
    printError(formatter.formatError(error, verbose: options.verbose))
    throw ExitCode(1)
}
```

| Command | Condition | Behavior |
|---------|-----------|----------|
| `rm` | Object doesn't exist | S3 `NoSuchKey` error propagates |
| `mv` | Source doesn't exist | S3 `NoSuchKey` error propagates |
| `mv` | Dest already exists | Allow overwrite (standard mv behavior) |
| `touch` | Object already exists | Custom error: "File already exists: {path}" |

## Success Messages

- `rm`: "Deleted {bucket}/{key}"
- `mv`: "Moved {src-bucket}/{src-key} to {dest-bucket}/{dest-key}"
- `touch`: "Created {bucket}/{key}"

## Files to Create

### Command Implementations

| File | Purpose |
|------|---------|
| `Sources/ss3/Commands/RemoveCommand.swift` | `ss3 rm` implementation |
| `Sources/ss3/Commands/MoveCommand.swift` | `ss3 mv` implementation |
| `Sources/ss3/Commands/TouchCommand.swift` | `ss3 touch` implementation |

### Unit Tests

| File | Test Cases |
|------|------------|
| `Tests/ss3Tests/RemoveCommandTests.swift` | Validation: rejects local, requires bucket+key, rejects directories |
| `Tests/ss3Tests/MoveCommandTests.swift` | Validation: both paths remote, requires bucket+key, rejects directories |
| `Tests/ss3Tests/TouchCommandTests.swift` | Validation: rejects local, requires bucket+key, rejects directories |

### Integration Tests

| File | Test Cases |
|------|------------|
| `Tests/ss3IntegrationTests/RemoveCommandIntegrationTests.swift` | Delete existing succeeds, delete non-existent fails |
| `Tests/ss3IntegrationTests/MoveCommandIntegrationTests.swift` | Move same bucket, move cross-bucket, move non-existent fails |
| `Tests/ss3IntegrationTests/TouchCommandIntegrationTests.swift` | Create new succeeds, touch existing fails, verify 0 bytes |

## Files to Modify

| File | Change |
|------|--------|
| `Sources/ss3/SS3.swift` | Add `RemoveCommand.self`, `MoveCommand.self`, `TouchCommand.self` to subcommands |

## Implementation Order

1. `rm` command + tests (simplest, single operation)
2. `touch` command + tests (single operation with pre-check)
3. `mv` command + tests (two operations, two path arguments)
