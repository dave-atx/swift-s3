import Foundation
import SwiftS3

struct HumanFormatter {
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

    func formatLsDate(_ date: Date) -> String {
        let now = Date()
        let sixMonthsAgo = now.addingTimeInterval(-182 * 24 * 60 * 60)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current

        if date >= sixMonthsAgo {
            // Recent: "Jan 28 14:30"
            formatter.dateFormat = "MMM dd HH:mm"
        } else {
            // Old: "Jan 28  2024" (two spaces before year)
            formatter.dateFormat = "MMM dd  yyyy"
        }

        return formatter.string(from: date)
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
