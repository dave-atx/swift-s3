import Foundation

struct SigV4Signer: Sendable {
    let accessKeyId: String
    let secretAccessKey: String
    let region: String
    let service: String = "s3"

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let amzDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    func dateStamp(for date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }

    func amzDate(for date: Date) -> String {
        Self.amzDateFormatter.string(from: date)
    }
}
