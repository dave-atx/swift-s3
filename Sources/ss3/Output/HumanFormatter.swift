import Foundation
import SwiftS3

struct HumanFormatter: OutputFormatter {
    func formatBuckets(_ buckets: [Bucket]) -> String {
        var lines: [String] = []

        for bucket in buckets {
            var line = bucket.name
            if let date = bucket.creationDate {
                line = "\(formatDate(date))  \(line)"
            }
            lines.append(line)
        }

        let summary = "\(buckets.count) bucket\(buckets.count == 1 ? "" : "s")"
        lines.append(summary)

        return lines.joined(separator: "\n")
    }

    func formatObjects(_ objects: [S3Object], prefixes: [String]) -> String {
        var lines: [String] = []
        var totalSize: Int64 = 0

        for prefix in prefixes.sorted() {
            let line = String(repeating: " ", count: 10) + "  " + String(repeating: " ", count: 16) + "  " + prefix
            lines.append(line)
        }

        for object in objects.sorted(by: { $0.key < $1.key }) {
            let sizeStr = object.size.map { formatSize($0) } ?? ""
            let dateStr = object.lastModified.map { formatDate($0) } ?? ""
            let paddedSize = sizeStr.padding(toLength: 10, withPad: " ", startingAt: 0)
            let paddedDate = dateStr.padding(toLength: 16, withPad: " ", startingAt: 0)
            let line = "\(paddedSize)  \(paddedDate)  \(object.key)"
            lines.append(line)
            totalSize += object.size ?? 0
        }

        let itemCount = objects.count + prefixes.count
        let summary = "\(itemCount) item\(itemCount == 1 ? "" : "s")" +
            (totalSize > 0 ? " (\(formatSize(totalSize)) total)" : "")
        lines.append(summary)

        return lines.joined(separator: "\n")
    }

    func formatError(_ error: any Error, verbose: Bool) -> String {
        if let s3Error = error as? S3APIError {
            var lines = ["Error: \(s3Error.message)"]

            if verbose {
                lines.append("Code: \(s3Error.code.rawValue)")
                if let resource = s3Error.resource {
                    lines.append("Resource: \(resource)")
                }
                if let requestId = s3Error.requestId {
                    lines.append("RequestId: \(requestId)")
                }
            }

            lines.append("Hint: \(hintForError(s3Error.code))")
            return lines.joined(separator: "\n")
        }

        return "Error: \(error.localizedDescription)"
    }

    func formatSuccess(_ message: String) -> String {
        message
    }

    func formatSize(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(Int(value)) \(units[unitIndex])"
        }
        return String(format: "%.1f %@", value, units[unitIndex])
    }

    func formatCompactSize(_ bytes: Int64) -> String {
        let units = ["B", "K", "M", "G", "T"]
        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        let unit = units[unitIndex]

        // For bytes (unitIndex == 0), format as integer right-aligned to 5 chars
        if unitIndex == 0 {
            return String(format: "%4d%@", Int(value), unit)
        }

        // For K and above: use decimal if < 100, no decimal if >= 100
        if value < 100 {
            return String(format: "%4.1f%@", value, unit)
        } else {
            return String(format: "%4.0f%@", value, unit)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    private func hintForError(_ code: S3APIError.Code) -> String {
        switch code {
        case .accessDenied:
            return "Check that your credentials have permission for this resource"
        case .noSuchBucket:
            return "The specified bucket does not exist"
        case .noSuchKey:
            return "The specified key does not exist in the bucket"
        case .invalidBucketName:
            return "Bucket names must be 3-63 characters, lowercase, and DNS-compliant"
        default:
            return "Check your request parameters and try again"
        }
    }
}
