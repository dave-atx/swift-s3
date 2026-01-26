# Profile CLI Option Design

**Issue:** https://github.com/dave-atx/swift-s3/issues/15
**Date:** 2026-01-25

## Overview

Replace `--endpoint`, `--region`, `--access-key`, `--secret-key`, `--b2`, and `--bucket` options with a single `--profile <name> <url>` option. This is a breaking change that simplifies configuration by encoding endpoint, credentials, bucket, and region in a URL.

## Requirements

- Single `--profile <name> <url>` option (required)
- Profile URL can contain credentials, bucket (virtual-host), and region
- Credentials can alternatively come from `SS3_<NAME>_ACCESS_KEY` / `SS3_<NAME>_SECRET_KEY` env vars
- New path format: `profile:bucket/key` instead of `s3://bucket/key`
- Remove all legacy options and `s3://` path format

## Profile URL Parsing

The `--profile <name> <url>` option defines a named S3 endpoint. The URL is parsed to extract:

**Components:**
- **Credentials**: From URL userinfo (`accessKey:secretKey@...`)
- **Bucket**: From virtual-host before `.s3.` (e.g., `mybucket.s3.region.example.com`)
- **Region**: From virtual-host after `.s3.` (e.g., `bucket.s3.us-west-2.example.com`)
- **Endpoint**: The full URL (credentials stripped for API calls)

**Fallbacks:**
- Region defaults to `"auto"` if not in URL
- Bucket is unspecified if not in URL (must be in path)
- Credentials fall back to `SS3_<NAME>_ACCESS_KEY` / `SS3_<NAME>_SECRET_KEY` env vars

**Parser logic:**
1. Parse URL, extract userinfo for credentials (if present)
2. If host contains `.s3.`:
   - Part before `.s3.` is bucket
   - Part after `.s3.` is region (everything up to TLD/port)
3. If host does NOT contain `.s3.`:
   - Bucket = nil (must be specified in path)
   - Region = "auto"
4. Rebuild endpoint URL without credentials

**Examples:**

| URL | Bucket | Region | Endpoint |
|-----|--------|--------|----------|
| `https://123:456@mybucket.s3.sjc-003.example.com` | mybucket | sjc-003 | `https://mybucket.s3.sjc-003.example.com` |
| `https://s3.us-west-2.amazonaws.com` | nil | us-west-2 | `https://s3.us-west-2.amazonaws.com` |
| `https://123.example.com/` | nil | auto | `https://123.example.com/` |
| `https://key:secret@storage.example.com` | nil | auto | `https://storage.example.com` |

## Path Parsing

The `S3Path` type distinguishes local paths from profile-based remote paths.

**Discriminator rule:** If path contains `:`, it's a profile path; otherwise it's local.

**Remote path format:** `profile:bucket/key` or `profile:` (for listing buckets)

**Parsing rules:**
- `e2:` / `e2:/` / `e2:.` → profile "e2", bucket = nil, key = nil (list buckets)
- `e2:mybucket` / `e2:mybucket/` → profile "e2", bucket = "mybucket", key = nil (list bucket root)
- `e2:mybucket/dir/file.txt` → profile "e2", bucket = "mybucket", key = "dir/file.txt"
- `file.txt` / `./file.txt` / `/path/to/file` → local path

**Updated type:**

```swift
enum S3Path: Equatable, Sendable {
    case local(String)
    case remote(profile: String, bucket: String?, key: String?)
}
```

**Bucket resolution:** If the profile URL contained a bucket (from virtual-host parsing), and the path specifies a bucket, the path bucket takes precedence. If neither specifies a bucket and one is required, error at execution time.

## GlobalOptions and Profile Management

**Removed options:**
- `--endpoint`
- `--region`
- `--access-key` / `--key-id`
- `--secret-key`
- `--b2`
- `--bucket`

**New options:**
- `--profile <name> <url>` (required, single)
- `--format` (unchanged)
- `--verbose` (unchanged)

**ArgumentParser structure:**

```swift
struct GlobalOptions: ParsableArguments {
    @Option(name: .long, parsing: .upToNextOption, help: "Profile: <name> <url>")
    var profile: [String] = []  // Captures exactly 2 values: name and url

    @Option var format: OutputFormat = .human
    @Flag var verbose: Bool = false
}
```

Validation ensures exactly 2 values in the `profile` array.

**Profile types:**

```swift
struct Profile: Sendable {
    let name: String
    let endpoint: URL
    let region: String
    let bucket: String?
    let accessKeyId: String?
    let secretAccessKey: String?

    static func parse(name: String, url: String) throws -> Profile
}

struct ResolvedProfile: Sendable {
    let name: String
    let endpoint: URL
    let region: String
    let bucket: String?
    let accessKeyId: String
    let secretAccessKey: String
}
```

Resolution merges URL-parsed values with environment variables. Error if credentials are missing from both sources.

**Path validation:** Since there's only one profile, paths using `profile:` format must use the name from `--profile`. Error if path uses a different profile name.

## Copy Command Directory Detection

When copying to a remote destination, the command checks if the destination is a directory by querying S3.

**Logic for `cp source dest`:**

1. Parse source and destination paths
2. If destination is remote (`profile:bucket/key`):
   - If key is empty or ends with `/` → treat as directory, append source filename
   - Otherwise, do a `listObjectsV2` with prefix `key/` and limit 1
     - If objects exist → it's a directory, append source filename
     - If no objects → treat as file path
3. If destination is local:
   - Check filesystem: `FileManager.default.fileExists(atPath:isDirectory:)`
   - If directory → append source filename

**Examples with profile `e2`:**

| Command | Detection | Result Key |
|---------|-----------|------------|
| `cp ./file.txt e2:bucket/` | Trailing slash | `file.txt` |
| `cp ./file.txt e2:bucket/dir/` | Trailing slash | `dir/file.txt` |
| `cp ./file.txt e2:bucket/dir` | Query S3 for `dir/` prefix | `dir/file.txt` if dir exists, else `dir` |
| `cp ./file.txt e2:bucket/newfile.txt` | Query S3 (empty) | `newfile.txt` |

**Error cases:**
- Source doesn't exist (local) → error
- Destination bucket doesn't exist → S3 API error

## Environment Variables

**Removed:**
- `SS3_ENDPOINT`
- `SS3_REGION`
- `SS3_ACCESS_KEY` / `SS3_KEY_ID`
- `SS3_SECRET_KEY`
- `SS3_BUCKET`

**New pattern:**
- `SS3_<NAME>_ACCESS_KEY` - Access key for profile `<NAME>`
- `SS3_<NAME>_SECRET_KEY` - Secret key for profile `<NAME>`

Where `<NAME>` is the profile name uppercased with non-alphanumeric characters replaced by underscores.

**Examples:**

```bash
# Profile named "e2"
SS3_E2_ACCESS_KEY=keyid123
SS3_E2_SECRET_KEY=secret456

# Profile named "prod-backup" (hyphen becomes underscore)
SS3_PROD_BACKUP_ACCESS_KEY=keyid789
SS3_PROD_BACKUP_SECRET_KEY=secret012
```

**Environment module:**

```swift
struct Environment: Sendable {
    func accessKey(for profile: String) -> String?
    func secretKey(for profile: String) -> String?

    private func envVarName(_ profile: String, suffix: String) -> String {
        let normalized = profile
            .uppercased()
            .replacing(/[^A-Z0-9]/, with: "_")
        return "SS3_\(normalized)_\(suffix)"
    }
}
```

## Command Updates

**ListCommand:**

```swift
struct ListCommand: AsyncParsableCommand {
    @OptionGroup var options: GlobalOptions

    @Argument(help: "Path to list (profile: or profile:bucket/prefix)")
    var path: String?
}
```

- If `path` is nil or `profile:` → list buckets
- If `path` is `profile:bucket/...` → list objects
- Validates path uses the defined profile name

**CopyCommand:**

```swift
struct CopyCommand: AsyncParsableCommand {
    @OptionGroup var options: GlobalOptions

    @Argument var source: String
    @Argument var destination: String

    @Option var multipartThreshold: Int = 100_000_000
    @Option var chunkSize: Int = 10_000_000
    @Option var parallel: Int = 4
}
```

- Validates exactly one local, one remote path
- Remote path must use defined profile name
- Directory detection via S3 query for remote destinations

**Usage examples:**

```bash
# List buckets
ss3 --profile e2 https://key:secret@s3.us-west-2.example.com ls e2:

# List objects in bucket
ss3 --profile e2 https://key:secret@s3.us-west-2.example.com ls e2:mybucket/prefix

# Upload file
ss3 --profile e2 https://key:secret@s3.us-west-2.example.com cp ./file.txt e2:mybucket/dir/

# Download file (credentials from env)
SS3_E2_ACCESS_KEY=xxx SS3_E2_SECRET_KEY=yyy \
ss3 --profile e2 https://s3.example.com cp e2:mybucket/file.txt ./local.txt
```

## Implementation Files

**Files to modify:**

| File | Changes |
|------|---------|
| `Sources/ss3/Configuration/GlobalOptions.swift` | Remove old options, add `--profile`, new parsing logic |
| `Sources/ss3/Configuration/S3Path.swift` | Update enum to `remote(profile:bucket:key:)`, new parsing for `profile:` format |
| `Sources/ss3/Configuration/Environment.swift` | Remove old vars, add `accessKey(for:)` / `secretKey(for:)` methods |
| `Sources/ss3/Configuration/ClientFactory.swift` | Update to accept `ResolvedProfile` instead of `ResolvedConfiguration` |
| `Sources/ss3/Commands/ListCommand.swift` | Update path handling, profile validation |
| `Sources/ss3/Commands/CopyCommand.swift` | Update path handling, add S3 directory detection query |

**New files:**

| File | Purpose |
|------|---------|
| `Sources/ss3/Configuration/Profile.swift` | `Profile` struct with URL parsing, `ResolvedProfile`, resolution logic |

**Test updates:**

| File | Changes |
|------|---------|
| `Tests/ss3Tests/GlobalOptionsTests.swift` | Update for new `--profile` option |
| `Tests/ss3Tests/S3PathTests.swift` | Update for `profile:` format |
| `Tests/ss3Tests/EnvironmentTests.swift` | Update for profile-based env vars |
| `Tests/ss3Tests/ProfileTests.swift` (new) | URL parsing, resolution logic |
