# Cross-Architecture Binary Stripping for Linux Releases

**Date:** 2026-01-30
**Status:** Implemented

## Problem

The Linux release CI job builds binaries for both x86_64 and aarch64 architectures using Swift's static Linux SDK. The workflow attempted to strip both binaries using the native `strip` command, which failed because:

- CI runs in x86_64 ubuntu-24.04 container
- Native `strip` cannot process aarch64 ELF binaries
- Error: "Unable to recognise the format of the input file"

Without stripping, binaries are ~175MB each due to debug symbols. Stripping reduces them to ~60-63MB (compressed: ~25-26MB).

## Solution

Install cross-architecture binutils and use architecture-specific strip tools.

### Implementation

Added two changes to `.github/workflows/release.yml`:

1. **Install cross-architecture binutils** (after SDK installation):
   ```yaml
   - name: Install cross-architecture binutils
     run: |
       apt-get update
       apt-get install -y binutils-aarch64-linux-gnu
   ```

2. **Use architecture-specific strip tools**:
   ```yaml
   - name: Strip binaries
     run: |
       strip .build/x86_64-swift-linux-musl/release/ss3
       aarch64-linux-gnu-strip .build/aarch64-swift-linux-musl/release/ss3
   ```

### Results

- **x86_64**: 176MB → 63MB (compressed: 26MB)
- **aarch64**: 175MB → 60MB (compressed: 25MB)
- **Total savings**: ~225MB across both binaries (~70MB in compressed archives)

### Alternatives Considered

1. **Split into separate native architecture jobs**: Would require arm64 GitHub runners (availability/cost concerns)
2. **Use llvm-strip**: Larger package install (~100MB vs ~4MB for binutils)
3. **Skip stripping aarch64**: Suboptimal - shipping 175MB binary unnecessarily

## Testing

Verified locally that:
- `binutils-aarch64-linux-gnu` package installs successfully
- `aarch64-linux-gnu-strip` correctly processes aarch64 binaries
- Both archives package correctly after stripping
- Binary size reductions match expectations

## Trade-offs

**Cost:** ~10-20 second CI overhead for apt package installation
**Benefit:** ~110MB reduction per architecture (~35MB in compressed form)

The size reduction is worth the minimal CI overhead, especially as releases are downloaded by end users.
