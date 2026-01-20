import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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

    func canonicalRequest(_ request: URLRequest, payloadHash: String) -> String {
        let method = request.httpMethod ?? "GET"

        let url = request.url!
        let path = url.path.isEmpty ? "/" : url.path

        let query = url.query ?? ""
        let sortedQuery = query
            .split(separator: "&")
            .sorted()
            .joined(separator: "&")

        // Get sorted headers (lowercase keys)
        var headers: [(String, String)] = []
        if let allHeaders = request.allHTTPHeaderFields {
            for (key, value) in allHeaders {
                headers.append((key.lowercased(), value))
            }
        }
        headers.sort { $0.0 < $1.0 }

        let canonicalHeaders = headers
            .map { "\($0.0):\($0.1)" }
            .joined(separator: "\n")

        let signedHeaders = headers
            .map { $0.0 }
            .joined(separator: ";")

        return """
            \(method)
            \(path)
            \(sortedQuery)
            \(canonicalHeaders)

            \(signedHeaders)
            \(payloadHash)
            """
    }

    func stringToSign(canonicalRequestHash: String, date: Date) -> String {
        let dateStamp = dateStamp(for: date)
        let amzDate = amzDate(for: date)
        let scope = "\(dateStamp)/\(region)/\(service)/aws4_request"

        return """
            AWS4-HMAC-SHA256
            \(amzDate)
            \(scope)
            \(canonicalRequestHash)
            """
    }

    func signingKey(for date: Date) -> Data {
        let dateStamp = dateStamp(for: date)
        let kSecret = "AWS4\(secretAccessKey)".data(using: .utf8)!
        let kDate = dateStamp.data(using: .utf8)!.hmacSHA256(key: kSecret)
        let kRegion = region.data(using: .utf8)!.hmacSHA256(key: kDate)
        let kService = service.data(using: .utf8)!.hmacSHA256(key: kRegion)
        let kSigning = "aws4_request".data(using: .utf8)!.hmacSHA256(key: kService)
        return kSigning
    }
}
