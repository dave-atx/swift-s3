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

    /// Environment variables for connecting to minio test server.
    static var minioEnv: [String: String] {
        [
            "SS3_ENDPOINT": MinioTestServer.endpoint,
            "SS3_REGION": "us-east-1",
            "SS3_KEY_ID": MinioTestServer.accessKey,
            "SS3_SECRET_KEY": MinioTestServer.secretKey,
            "SS3_PATH_STYLE": "true"
        ]
    }

    /// Runs ss3 with the given arguments.
    /// - Parameters:
    ///   - args: Command line arguments (e.g., "ls", "s3://bucket")
    ///   - env: Additional environment variables to merge with minio config
    /// - Returns: CLIResult with exit code and captured output
    static func run(_ args: String..., env: [String: String] = [:]) async throws -> CLIResult {
        try await run(arguments: args, env: env)
    }

    /// Runs ss3 with the given arguments array.
    static func run(arguments: [String], env: [String: String] = [:]) async throws -> CLIResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments

        // Merge base minio env with any custom env
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in minioEnv {
            environment[key] = value
        }
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
