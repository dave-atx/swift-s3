# Release Workflow Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create GitHub Actions workflow that builds and releases CLI binaries when a tag is pushed.

**Architecture:** Tag-triggered workflow runs all tests, then builds 4 platform binaries (macOS arm64/amd64, Linux arm64/amd64), packages them as tarballs with checksums, and creates a GitHub release.

**Tech Stack:** GitHub Actions, Swift 6.2, Swift Static Linux SDK, softprops/action-gh-release

---

## Task 1: Add Version Conditional Compilation to SS3.swift

**Files:**
- Modify: `Sources/ss3/SS3.swift`

**Step 1: Modify SS3.swift to use conditional VERSION**

Replace the hardcoded version with conditional compilation:

```swift
import ArgumentParser

@main
struct SS3: AsyncParsableCommand {
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
}
```

**Step 2: Test that default build shows "dev" version**

Run: `swift build && .build/debug/ss3 --version`
Expected: Output shows `dev`

**Step 3: Test that VERSION flag injection works**

Run: `swift build -Xswiftc -DVERSION='\"v0.2.0\"' && .build/debug/ss3 --version`
Expected: Output shows `v0.2.0`

**Step 4: Run linter**

Run: `swiftlint --strict`
Expected: No violations

**Step 5: Run existing tests to ensure no regression**

Run: `swift test --filter ss3Tests`
Expected: All tests pass

**Step 6: Commit**

```bash
git add Sources/ss3/SS3.swift
git commit -m "feat(ss3): add build-time version injection

Use conditional compilation to inject version from build flags.
Local builds show 'dev', CI release builds show the git tag.

Closes #25"
```

---

## Task 2: Create Release Workflow - Test Jobs

**Files:**
- Create: `.github/workflows/release.yml`

**Step 1: Create release.yml with trigger and test jobs**

Create `.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  lint:
    name: SwiftLint
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - name: Install SwiftLint
        run: brew install swiftlint
      - name: Run SwiftLint
        run: swiftlint --strict

  unit-tests-macos:
    name: Unit Tests (macOS)
    needs: lint
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - name: Build
        run: swift build
      - name: Run SwiftS3 Tests
        run: swift test --filter SwiftS3Tests
      - name: Run ss3 Tests
        run: swift test --filter ss3Tests

  unit-tests-linux:
    name: Unit Tests (Linux)
    needs: lint
    runs-on: ubuntu-24.04
    container:
      image: swift:6.2-noble
    steps:
      - uses: actions/checkout@v4
      - name: Build
        run: swift build
      - name: Run SwiftS3 Tests
        run: swift test --filter SwiftS3Tests
      - name: Run ss3 Tests
        run: swift test --filter ss3Tests

  integration-tests-macos:
    name: Integration Tests (macOS)
    needs: lint
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - name: Setup minio
        run: ./Scripts/setup-minio.sh
      - name: Build
        run: swift build
      - name: Run Library Integration Tests
        run: swift test --filter IntegrationTests --no-parallel
      - name: Run CLI Integration Tests
        run: swift test --filter ss3IntegrationTests --no-parallel

  integration-tests-linux:
    name: Integration Tests (Linux)
    needs: lint
    runs-on: ubuntu-24.04
    container:
      image: swift:6.2-noble
    steps:
      - uses: actions/checkout@v4
      - name: Install curl
        run: apt-get update && apt-get install -y curl
      - name: Setup minio
        run: ./Scripts/setup-minio.sh
      - name: Build
        run: swift build
      - name: Run Library Integration Tests
        run: swift test --filter IntegrationTests --no-parallel
      - name: Run CLI Integration Tests
        run: swift test --filter ss3IntegrationTests --no-parallel
```

**Step 2: Validate YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))"`
Expected: No errors (silent success)

**Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add release workflow test jobs

Add tag-triggered workflow with lint, unit tests, and integration
tests for both macOS and Linux platforms."
```

---

## Task 3: Add macOS Build Job

**Files:**
- Modify: `.github/workflows/release.yml`

**Step 1: Add build-macos job after the test jobs**

Append to `.github/workflows/release.yml`:

```yaml

  build-macos:
    name: Build macOS
    needs: [unit-tests-macos, unit-tests-linux, integration-tests-macos, integration-tests-linux]
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4

      - name: Build arm64
        run: |
          swift build -c release --arch arm64 \
            -Xswiftc -DVERSION='\"${{ github.ref_name }}\"'

      - name: Build x86_64
        run: |
          swift build -c release --arch x86_64 \
            -Xswiftc -DVERSION='\"${{ github.ref_name }}\"'

      - name: Package arm64
        run: |
          tar -czvf ss3-${{ github.ref_name }}-macos-arm64.tar.gz \
            -C .build/arm64-apple-macosx/release ss3

      - name: Package x86_64
        run: |
          tar -czvf ss3-${{ github.ref_name }}-macos-amd64.tar.gz \
            -C .build/x86_64-apple-macosx/release ss3

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: macos-binaries
          path: ss3-*.tar.gz
```

**Step 2: Validate YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))"`
Expected: No errors

**Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add macOS build job to release workflow

Build arm64 and x86_64 binaries with version injection,
package as tarballs, and upload as artifacts."
```

---

## Task 4: Add Linux Build Job

**Files:**
- Modify: `.github/workflows/release.yml`

**Step 1: Add build-linux job**

Append to `.github/workflows/release.yml`:

```yaml

  build-linux:
    name: Build Linux
    needs: [unit-tests-macos, unit-tests-linux, integration-tests-macos, integration-tests-linux]
    runs-on: ubuntu-24.04
    container:
      image: swift:6.2-noble
    steps:
      - uses: actions/checkout@v4

      - name: Install Swift Static Linux SDK
        run: |
          swift sdk install https://download.swift.org/swift-6.2-release/static-sdk/swift-6.2-RELEASE/swift-6.2-RELEASE_static-linux-0.0.1.artifactbundle.tar.gz

      - name: Build x86_64
        run: |
          swift build -c release --swift-sdk x86_64-swift-linux-musl \
            -Xswiftc -DVERSION='\"${{ github.ref_name }}\"'

      - name: Build arm64
        run: |
          swift build -c release --swift-sdk aarch64-swift-linux-musl \
            -Xswiftc -DVERSION='\"${{ github.ref_name }}\"'

      - name: Package x86_64
        run: |
          tar -czvf ss3-${{ github.ref_name }}-linux-amd64.tar.gz \
            -C .build/x86_64-swift-linux-musl/release ss3

      - name: Package arm64
        run: |
          tar -czvf ss3-${{ github.ref_name }}-linux-arm64.tar.gz \
            -C .build/aarch64-swift-linux-musl/release ss3

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: linux-binaries
          path: ss3-*.tar.gz
```

**Step 2: Validate YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))"`
Expected: No errors

**Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add Linux build job to release workflow

Build static x86_64 and arm64 binaries using Swift Static Linux SDK,
package as tarballs, and upload as artifacts."
```

---

## Task 5: Add Release Job

**Files:**
- Modify: `.github/workflows/release.yml`

**Step 1: Add release job**

Append to `.github/workflows/release.yml`:

```yaml

  release:
    name: Create Release
    needs: [build-macos, build-linux]
    runs-on: ubuntu-24.04
    permissions:
      contents: write
    steps:
      - name: Download macOS artifacts
        uses: actions/download-artifact@v4
        with:
          name: macos-binaries

      - name: Download Linux artifacts
        uses: actions/download-artifact@v4
        with:
          name: linux-binaries

      - name: Generate checksums
        run: sha256sum ss3-*.tar.gz > checksums.txt

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: |
            ss3-*.tar.gz
            checksums.txt
          generate_release_notes: true
```

**Step 2: Validate YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))"`
Expected: No errors

**Step 3: Validate complete workflow with actionlint (optional)**

Run: `which actionlint && actionlint .github/workflows/release.yml || echo "actionlint not installed, skipping"`
Expected: No errors (or skip message)

**Step 4: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add release job to create GitHub release

Download all build artifacts, generate SHA256 checksums,
and create GitHub release with tarballs and checksums.txt."
```

---

## Task 6: Final Verification and Squash

**Step 1: Review the complete release.yml**

Run: `cat .github/workflows/release.yml`
Expected: Complete workflow with all 8 jobs (lint, 4 test jobs, 2 build jobs, release)

**Step 2: Run linter one final time**

Run: `swiftlint --strict`
Expected: No violations

**Step 3: Run all unit tests**

Run: `swift test --filter SwiftS3Tests && swift test --filter ss3Tests`
Expected: All tests pass

**Step 4: Verify version injection still works**

Run: `swift build -Xswiftc -DVERSION='\"v0.2.0\"' && .build/debug/ss3 --version`
Expected: Output shows `v0.2.0`

**Step 5: Interactive rebase to squash commits (optional)**

If you want a single commit for the PR:
```bash
git rebase -i HEAD~5
# Mark all but first as "squash"
# Edit commit message to:
# "feat: add GitHub Actions release workflow (#25)"
```

Or keep granular commits for easier review.

---

## Verification Checklist

After implementation, verify:

- [ ] `ss3 --version` shows `dev` for local builds
- [ ] `ss3 --version` shows injected version when built with `-DVERSION`
- [ ] `.github/workflows/release.yml` exists with valid YAML
- [ ] Workflow triggers on `v*` tags only
- [ ] All test jobs depend on lint
- [ ] Build jobs depend on all test jobs
- [ ] Release job depends on both build jobs
- [ ] Release job has `contents: write` permission
- [ ] `swiftlint --strict` passes
- [ ] All existing tests pass
