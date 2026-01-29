> [!CAUTION]
> This is currently in progress and not yet useful for public consumption

swift library and command line tool for interacting with s3 API compatible services.

## Development

### Linting on Linux

SwiftLint requires the SourceKit library on Linux. Set the `LINUX_SOURCEKIT_LIB_PATH` environment variable to point to your Swift toolchain's lib directory:

```bash
# For swiftly-managed toolchains (bash/zsh)
export LINUX_SOURCEKIT_LIB_PATH="$(swiftly use --print-location)/usr/lib"

# For swiftly-managed toolchains (fish)
set -gx LINUX_SOURCEKIT_LIB_PATH (swiftly use --print-location)/usr/lib

# For system Swift installations
export LINUX_SOURCEKIT_LIB_PATH=/usr/lib/swift/lib
```
