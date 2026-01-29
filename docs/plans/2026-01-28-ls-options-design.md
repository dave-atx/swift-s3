# Design: Add ls Options (Issue #23)

## Overview

Enhance the `ss3 ls` command with Unix-style options for long format and time-based sorting. Remove JSON/TSV output formats to simplify the interface.

## Command Interface

```
ss3 ls [OPTIONS] <path>

Options:
  -l, -h          Long format (size, date, name)
  -t              Sort by modification time, most recent first
```

**Removed:** `--format` option (json, tsv, human)

### Examples

```bash
# Default: names only, one per line
ss3 ls profile:bucket/
documents/
photo.jpg
notes.txt

# Long format
ss3 ls -l profile:bucket/
documents/
 1.2M  Jan 28 14:30  photo.jpg
  45K  Dec 15  2024  notes.txt

# Sorted by time
ss3 ls -t profile:bucket/
photo.jpg
notes.txt
documents/

# Combined
ss3 ls -lt profile:bucket/
 1.2M  Jan 28 14:30  photo.jpg
  45K  Dec 15  2024  notes.txt
documents/
```

## Output Formatting

### Size Column (long format only)

- Right-aligned, 5 characters wide
- Format examples: `999B`, `1.0K`, `99.9K`, `100K`, `1.0M`, `1.0G`, `1.0T`
- Units: B, K, M, G, T (single letter)

### Date Column (long format only)

- 12 characters wide
- Recent (<6 months): `Jan 28 14:30`
- Older (>=6 months): `Jan 28  2024` (two spaces before year)

### Column Layout

```
<size>  <date>        <name>
 1.2M  Jan 28 14:30  photo.jpg
99.9K  Dec 15  2024  archive.zip
```

Two spaces between columns.

### Directories

- Always display name only with trailing `/`
- No size/date columns even in long format
- Listed on their own line

### No Summary Line

Remove the current "N items (X total)" summary to match Unix `ls` behavior.

## Sorting Behavior

### Default (no `-t`)

Output in S3 API's natural order (typically lexicographic).

### With `-t` Flag

1. Files sorted by modification time, most recent first
2. Directories listed after all files, sorted alphabetically

## Bucket Listings

The same options apply when listing buckets.

### Default

```
ss3 ls profile:
my-bucket
other-bucket
```

### Long Format (`-l`)

```
ss3 ls -l profile:
Jan 15  2024  my-bucket
Mar 20 10:30  other-bucket
```

No size column (S3 doesn't provide bucket size).

### Sorted by Time (`-t`)

Buckets sorted by creation date, most recent first.

## Implementation Changes

### Files to Modify

1. **`ListCommand.swift`**
   - Add `-l`, `-h`, `-t` flags using ArgumentParser
   - Remove dependency on `--format` option
   - Pass formatting options to output logic

2. **`HumanFormatter.swift`**
   - Rewrite `formatObjects()` to support short/long modes
   - Rewrite `formatBuckets()` to support short/long modes
   - Add sorting logic
   - New helpers: `formatCompactSize()`, `formatLsDate()`

3. **`GlobalOptions.swift`**
   - Remove `--format` option

### Files to Remove

- `JSONFormatter.swift`
- `TSVFormatter.swift`
- `OutputFormat.swift`

### Files Unchanged

- `S3Client`, `S3Path`, `ConfigFile`, other commands

## Testing Strategy

### Unit Tests

1. **Size formatting**
   - `0` -> `0B`
   - `999` -> `999B`
   - `1024` -> `1.0K`
   - `102400` -> `100K`
   - `1048576` -> `1.0M`
   - TB range values

2. **Date formatting**
   - Recent date (< 6 months) -> `Jan 28 14:30`
   - Old date (>= 6 months) -> `May 15  2025`
   - Edge case: exactly 6 months

3. **Output formatting**
   - Short format: names only
   - Long format: column alignment
   - Mixed files and directories
   - Empty listings

4. **Sorting**
   - Files by date, most recent first
   - Directories alphabetically after files

### Integration Tests (minio)

1. `ls` default - names only
2. `ls -l` - long format
3. `ls -h` - same as `-l`
4. `ls -t` - time sorted
5. `ls -lt` - combined
6. Bucket listing with all flag combinations
