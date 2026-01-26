# Config File for Profile Configuration

**Issue:** #17
**Date:** 2026-01-26

## Summary

Add support for a config file at `$XDG_CONFIG_HOME/ss3/profiles.json` to store profile URLs, enabling shorter commands without repeated `--profile` flags.

## Config File

**Location:**
- `$XDG_CONFIG_HOME/ss3/profiles.json`
- Falls back to `~/.config/ss3/profiles.json` when `XDG_CONFIG_HOME` is unset

**Format:**
```json
{
  "e2": "https://123:456@bucket.s3.us-west-001.example.com",
  "r2": "https://account.r2.cloudflarestorage.com"
}
```

Simple key-value mapping: profile name to endpoint URL. URLs may contain embedded credentials.

**Error handling:**
- Missing file: silently proceed (config is optional)
- Malformed JSON or unreadable: fail with clear error message
- Empty file `{}`: valid, no profiles defined

## Profile Resolution

When a path like `e2:bucket/key` is used, the CLI looks up profile "e2" automatically from the config file.

**Precedence (highest to lowest):**
1. `--profile name url` on command line (complete override)
2. Config file lookup by profile name extracted from path

**Examples:**
```bash
# Config has "e2" defined
ss3 ls e2:mybucket              # looks up "e2" from config
ss3 cp e2:bucket/file ./        # looks up "e2" from config

# Override config with --profile
ss3 --profile e2 https://other.url ls e2:mybucket  # uses CLI URL

# No config, no --profile for unknown profile
ss3 ls unknown:mybucket         # error with available profiles
```

**Error when profile not found:**
```
Unknown profile 'e2'. Available profiles: b2, r2, gcs
Use --profile <name> <url> to specify endpoint.
```

## Credential Resolution

**Precedence (highest to lowest):**
1. Environment variables: `SS3_<NAME>_ACCESS_KEY` and `SS3_<NAME>_SECRET_KEY`
2. Credentials embedded in URL: `https://key:secret@endpoint.com`

This allows sharing config files without secrets while credentials come from environment.

**Examples:**
```bash
# Config: {"e2": "https://key:secret@s3.example.com"}
ss3 ls e2:mybucket              # uses credentials from URL

# Environment overrides URL credentials
SS3_E2_ACCESS_KEY=newkey SS3_E2_SECRET_KEY=newsecret ss3 ls e2:mybucket

# Config without credentials requires env vars
# Config: {"e2": "https://s3.example.com"}
SS3_E2_ACCESS_KEY=key SS3_E2_SECRET_KEY=secret ss3 ls e2:mybucket
```

## Implementation

### New File: `Sources/ss3/Configuration/ConfigFile.swift`

```swift
struct ConfigFile: Sendable {
    let profiles: [String: String]  // name -> URL

    static func load(from path: String? = nil) throws -> ConfigFile?
    static func defaultPath() -> String?
    func profileURL(for name: String) -> String?
    var availableProfiles: [String] { get }
}
```

Responsibilities:
- Determine XDG config path
- Load and parse JSON
- Look up profile URL by name
- Return available profile names for error messages

### Modified: `GlobalOptions.swift`

- `--profile` continues to require two arguments (name + URL)
- Acts purely as override mechanism

### Modified: `Profile.swift`

Add factory method:
```swift
extension Profile {
    static func fromConfig(_ config: ConfigFile, name: String) throws -> Profile
}
```

### Modified: Commands

Update `ListCommand.swift` and `CopyCommand.swift`:
1. Load config file at startup
2. Extract profile name from path argument
3. Check for `--profile` override first
4. Fall back to config file lookup
5. Show available profiles on unknown profile error

### Unchanged

- `S3Path.swift` - path parsing unchanged
- `Environment.swift` - env var handling unchanged
- `ClientFactory.swift` - client creation unchanged
- `SwiftS3` library - no changes needed
- Formatters - no changes needed

## Testing

### Unit Tests

**`ConfigFileTests.swift`** (new):
- Parse valid JSON with multiple profiles
- Handle missing file gracefully
- Error on malformed JSON
- Error on unreadable file
- XDG_CONFIG_HOME resolution with custom env

**`ProfileResolutionTests.swift`** (new or extend existing):
- Profile lookup from config succeeds
- `--profile` flag overrides config
- Unknown profile error shows available profiles
- Credential precedence: env vars override URL

### Integration Tests

- Full CLI flow with temporary config file
- Commands work with config-based profiles
- Override behavior with `--profile` flag

### Test Approach

- `ConfigFile.load(from:)` accepts optional path for testing
- Use temp directories for integration tests
- Injectable `Environment` for credential tests
