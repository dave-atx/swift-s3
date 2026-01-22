import Foundation
import SwiftS3

struct TSVFormatter: OutputFormatter {
    func formatBuckets(_ buckets: [Bucket]) -> String {
        buckets.map { bucket in
            let date = bucket.creationDate.map { formatISO8601($0) } ?? ""
            return "\(bucket.name)\t\(date)"
        }.joined(separator: "\n")
    }

    func formatObjects(_ objects: [S3Object], prefixes: [String]) -> String {
        var lines = prefixes.map { "\($0)\t0\t" }

        lines += objects.map { object in
            let size = object.size ?? 0
            let date = object.lastModified.map { formatISO8601($0) } ?? ""
            return "\(object.key)\t\(size)\t\(date)"
        }

        return lines.joined(separator: "\n")
    }

    func formatError(_ error: any Error, verbose: Bool) -> String {
        if let s3Error = error as? S3APIError {
            if verbose {
                return "ERROR\t\(s3Error.code.rawValue)\t\(s3Error.message)"
            }
            return "ERROR\t\(s3Error.message)"
        }
        return "ERROR\t\(error.localizedDescription)"
    }

    func formatSuccess(_ message: String) -> String {
        "OK\t\(message)"
    }

    private func formatISO8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }
}
