import Foundation

/// Result of running an ss3 CLI command.
struct CLIResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }
}

/// Runs the ss3 CLI binary and captures output.
enum CLIRunner {
    /// Profile name used for minio tests.
    static let profileName = "minio"

    /// Profile URL for minio test server.
    static var profileURL: String {
        let endpoint = MinioTestServer.endpoint
        return "\(endpoint.replacingOccurrences(of: "http://", with: "http://\(MinioTestServer.accessKey):\(MinioTestServer.secretKey)@"))"
    }

    /// Path to the built ss3 binary.
    static var binaryPath: String {
        // Swift test runs from package directory, binary is in .build/debug/
        let possiblePaths = [
            ".build/debug/ss3",
            "../.build/debug/ss3",
            "../../.build/debug/ss3"
        ]

        for path in possiblePaths where FileManager.default.fileExists(atPath: path) {
            return path
        }

        // Fall back to building the path from current directory
        let cwd = FileManager.default.currentDirectoryPath
        return "\(cwd)/.build/debug/ss3"
    }

    /// Base arguments for profile-based CLI invocation.
    static var baseArgs: [String] {
        ["--profile", profileName, profileURL, "--path-style"]
    }

    /// Runs ss3 with the given arguments.
    /// - Parameters:
    ///   - args: Command line arguments (e.g., "ls", "minio:bucket")
    ///   - env: Additional environment variables
    /// - Returns: CLIResult with exit code and captured output
    static func run(_ args: String..., env: [String: String] = [:]) async throws -> CLIResult {
        try await run(arguments: args, env: env)
    }

    /// Runs ss3 with the given arguments array.
    static func run(arguments: [String], env: [String: String] = [:]) async throws -> CLIResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = baseArgs + arguments

        // Use process environment with any custom additions
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in env {
            environment[key] = value
        }
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return CLIResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}
