import SwiftS3

protocol OutputFormatter: Sendable {
    func formatBuckets(_ buckets: [Bucket]) -> String
    func formatObjects(_ objects: [S3Object], prefixes: [String]) -> String
    func formatError(_ error: any Error, verbose: Bool) -> String
    func formatSuccess(_ message: String) -> String
}
