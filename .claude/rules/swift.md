swift code rules
-----
- Use swift 6.2.x
- Use swift strict concurrency
- Must work on both macOS 26+ and Linux (using the Swift Static Linux SDK)
- Do not use external libraries
- Do not use `unsafe`, `@unchecked`, or `nonisolated(unsafe)` - prefer safe alternatives
- Use Swift Plugin Manager and Swift Test
- **MUST pass swiftlint --strict on both macOS and Linux before any commit**