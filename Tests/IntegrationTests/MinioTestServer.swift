import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Manages a minio server process for integration testing.
/// Call `ensureRunning()` before tests and `stop()` after.
actor MinioTestServer {
    static let shared = MinioTestServer()

    static let port = 9199
    static let accessKey = "minioadmin"
    static let secretKey = "minioadmin"
    static let endpoint = "http://127.0.0.1:\(port)"

    static var endpointURL: URL {
        guard let url = URL(string: endpoint) else {
            fatalError("Invalid minio endpoint URL: \(endpoint)")
        }
        return url
    }

    private var process: Process?
    private var dataDirectory: URL?
    private var isRunning = false

    private init() {}

    /// Ensures the minio server is running. Safe to call multiple times.
    func ensureRunning() async throws {
        if isRunning {
            return
        }

        let minioBinary = findMinioBinary()
        guard FileManager.default.fileExists(atPath: minioBinary) else {
            throw MinioError.binaryNotFound(
                "minio binary not found at \(minioBinary). Run ./Scripts/setup-minio.sh first."
            )
        }

        // Create temp data directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("minio-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        dataDirectory = tempDir

        // Start minio process
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: minioBinary)
        proc.arguments = ["server", tempDir.path, "--address", ":\(Self.port)"]

        // Inherit current environment and add minio-specific vars
        var environment = ProcessInfo.processInfo.environment
        environment["MINIO_ROOT_USER"] = Self.accessKey
        environment["MINIO_ROOT_PASSWORD"] = Self.secretKey
        proc.environment = environment

        // Suppress output
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        try proc.run()
        process = proc
        isRunning = true

        // Wait for server to be ready
        try await waitForReady()
    }

    /// Stops the minio server and cleans up data directory.
    func stop() async {
        if let proc = process, proc.isRunning {
            proc.terminate()
            proc.waitUntilExit()
        }
        process = nil
        isRunning = false

        // Clean up data directory
        if let dataDir = dataDirectory {
            try? FileManager.default.removeItem(at: dataDir)
        }
        dataDirectory = nil
    }

    /// Polls the minio health endpoint until the server is ready.
    private func waitForReady() async throws {
        let healthURL = Self.endpointURL.appendingPathComponent("minio/health/live")
        let maxAttempts = 30
        let delayNanoseconds: UInt64 = 100_000_000 // 100ms

        for attempt in 1...maxAttempts {
            do {
                let (_, response) = try await URLSession.shared.data(from: healthURL)
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200 {
                    return
                }
            } catch {
                // Server not ready yet
            }

            if attempt == maxAttempts {
                throw MinioError.serverNotReady("minio server did not become ready after \(maxAttempts) attempts")
            }

            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
    }

    private func findMinioBinary() -> String {
        // Look relative to the test file location
        // Tests run from the package root, so .minio/minio should work
        let possiblePaths = [
            ".minio/minio",
            "../.minio/minio",
            "../../.minio/minio"
        ]

        for path in possiblePaths where FileManager.default.fileExists(atPath: path) {
            return path
        }

        // Fall back to absolute path from current directory
        let cwd = FileManager.default.currentDirectoryPath
        return "\(cwd)/.minio/minio"
    }
}

enum MinioError: Error, CustomStringConvertible {
    case binaryNotFound(String)
    case serverNotReady(String)

    var description: String {
        switch self {
        case .binaryNotFound(let msg): return msg
        case .serverNotReady(let msg): return msg
        }
    }
}
