# GitHub Actions Release Workflow Design

**Issue:** #25 - Actions for CLI release creation
**Date:** 2026-01-29

## Overview

Create a GitHub Actions workflow that builds and releases CLI binaries when a tag is pushed to main. The version reported by the CLI matches the tag name.

## Requirements

1. Version in CLI matches git tag (e.g., `v0.2`)
2. Build binaries for 4 platforms:
   - Linux x86_64 (amd64)
   - Linux arm64
   - macOS arm64
   - macOS x86_64 (amd64)
3. Run all tests (unit + integration) on all platforms before release
4. Only create release if all tests pass
5. Linux binaries built with Swift Static Linux SDK (musl, no glibc dependency)

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Version injection | Build-time compiler flag | Clean, no source modification during CI |
| Linux binary builds | Ubuntu 24.04 with Swift Static SDK | Static binaries, built on Linux |
| macOS binary builds | macOS 26 native | Native arm64, cross-compile x86_64 |
| Workflow structure | Separate release.yml | Clean separation from CI |
| Test jobs | Duplicated from ci.yml | Simple, stable, avoids workflow_call complexity |
| Asset naming | Tarballs with version | `ss3-v0.2-macos-arm64.tar.gz` |
| Checksums | SHA256 in checksums.txt | Standard integrity verification |

## Workflow Structure

**File:** `.github/workflows/release.yml`

**Trigger:**
```yaml
on:
  push:
    tags:
      - 'v*'
```

**Job Dependency Chain:**
```
lint
  └─> unit-tests-macos ─────┐
  └─> unit-tests-linux ─────┤
  └─> integration-tests-macos ─┤
  └─> integration-tests-linux ─┴─> build-macos ─┐
                                   build-linux ─┴─> release
```

## Jobs

### lint
- **Runner:** macos-26
- **Action:** Run `swiftlint --strict`

### unit-tests-macos
- **Runner:** macos-26
- **Needs:** lint
- **Action:** `swift test --filter SwiftS3Tests` and `swift test --filter ss3Tests`

### unit-tests-linux
- **Runner:** ubuntu-24.04
- **Container:** swift:6.2-noble
- **Needs:** lint
- **Action:** `swift test --filter SwiftS3Tests` and `swift test --filter ss3Tests`

### integration-tests-macos
- **Runner:** macos-26
- **Needs:** lint
- **Action:** Setup minio, run IntegrationTests and ss3IntegrationTests

### integration-tests-linux
- **Runner:** ubuntu-24.04
- **Container:** swift:6.2-noble
- **Needs:** lint
- **Action:** Setup minio, run IntegrationTests and ss3IntegrationTests

### build-macos
- **Runner:** macos-26
- **Needs:** all test jobs
- **Actions:**
  1. Build arm64: `swift build -c release --arch arm64 -Xswiftc -DVERSION=\"${{ github.ref_name }}\"`
  2. Build x86_64: `swift build -c release --arch x86_64 -Xswiftc -DVERSION=\"${{ github.ref_name }}\"`
  3. Package tarballs:
     - `ss3-{tag}-macos-arm64.tar.gz`
     - `ss3-{tag}-macos-amd64.tar.gz`
  4. Upload artifacts

### build-linux
- **Runner:** ubuntu-24.04
- **Container:** swift:6.2-noble
- **Needs:** all test jobs
- **Actions:**
  1. Install Swift Static Linux SDKs
  2. Build x86_64: `swift build -c release --swift-sdk x86_64-swift-linux-musl -Xswiftc -DVERSION=\"${{ github.ref_name }}\"`
  3. Build arm64: `swift build -c release --swift-sdk aarch64-swift-linux-musl -Xswiftc -DVERSION=\"${{ github.ref_name }}\"`
  4. Package tarballs:
     - `ss3-{tag}-linux-amd64.tar.gz`
     - `ss3-{tag}-linux-arm64.tar.gz`
  5. Upload artifacts

### release
- **Runner:** ubuntu-24.04
- **Needs:** build-macos, build-linux
- **Permissions:** contents: write
- **Actions:**
  1. Download all artifacts
  2. Generate checksums.txt with SHA256 hashes
  3. Create GitHub release using softprops/action-gh-release@v2
  4. Attach all tarballs and checksums.txt

## Code Changes

### Sources/ss3/SS3.swift

Change version from hardcoded string to conditional compilation:

```swift
static let configuration = CommandConfiguration(
    commandName: "ss3",
    abstract: "A CLI for S3-compatible storage services",
    #if VERSION
    version: VERSION,
    #else
    version: "dev",
    #endif
    subcommands: [ListCommand.self, CopyCommand.self, RemoveCommand.self, TouchCommand.self, MoveCommand.self],
    defaultSubcommand: nil
)
```

## Release Assets

Example for tag `v0.2`:

| Asset | Description |
|-------|-------------|
| `ss3-v0.2-macos-arm64.tar.gz` | macOS Apple Silicon binary |
| `ss3-v0.2-macos-amd64.tar.gz` | macOS Intel binary |
| `ss3-v0.2-linux-arm64.tar.gz` | Linux ARM64 static binary |
| `ss3-v0.2-linux-amd64.tar.gz` | Linux x86_64 static binary |
| `checksums.txt` | SHA256 checksums for all tarballs |

## Implementation Steps

1. Modify `Sources/ss3/SS3.swift` to use conditional version compilation
2. Create `.github/workflows/release.yml` with all jobs
3. Test locally that version flag works: `swift build -Xswiftc -DVERSION=\"v0.1.0\"`
4. Create a test tag to verify workflow
