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
        let credentials = "\(MinioTestServer.accessKey):\(MinioTestServer.secretKey)"
        return endpoint.replacingOccurrences(of: "http://", with: "http://\(credentials)@")
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

    /// Profile arguments for CLI invocation.
    static var profileArgs: [String] {
        ["--profile", profileName, profileURL, "--path-style"]
    }

    /// Creates a temporary config file for testing.
    static func createTempConfig() throws -> URL {
        let configDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ss3-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        let ss3Dir = configDir.appendingPathComponent("ss3")
        try FileManager.default.createDirectory(at: ss3Dir, withIntermediateDirectories: true)

        let configFile = ss3Dir.appendingPathComponent("profiles.json")
        let config = """
        {
          "\(profileName)": "\(profileURL)"
        }
        """
        try config.write(to: configFile, atomically: true, encoding: .utf8)
        return configDir
    }

    /// Runs ss3 with the given arguments.
    /// - Parameters:
    ///   - args: Command line arguments (e.g., "ls", "minio:bucket")
    ///   - env: Additional environment variables
    ///   - useConfig: If true, use config file instead of --profile flag
    /// - Returns: CLIResult with exit code and captured output
    static func run(_ args: String..., env: [String: String] = [:], useConfig: Bool = false) async throws -> CLIResult {
        try await run(arguments: args, env: env, useConfig: useConfig)
    }

    /// Runs ss3 with the given arguments array.
    /// Arguments: first arg is the subcommand, profile options are inserted after it.
    static func run(
        arguments: [String],
        env: [String: String] = [:],
        useConfig: Bool = false
    ) async throws -> CLIResult {
        var fullArgs: [String] = []
        var environment = ProcessInfo.processInfo.environment

        for (key, value) in env {
            environment[key] = value
        }

        if useConfig {
            let configDir = try createTempConfig()
            environment["XDG_CONFIG_HOME"] = configDir.path

            if let subcommand = arguments.first {
                fullArgs.append(subcommand)
                fullArgs.append("--path-style")
                fullArgs.append(contentsOf: arguments.dropFirst())
            }
        } else {
            if let subcommand = arguments.first {
                fullArgs.append(subcommand)
                fullArgs.append(contentsOf: profileArgs)
                fullArgs.append(contentsOf: arguments.dropFirst())
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = fullArgs
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
