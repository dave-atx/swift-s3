import Foundation
import SwiftS3

struct JSONFormatter: OutputFormatter {
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    func formatBuckets(_ buckets: [Bucket]) -> String {
        let items = buckets.map { BucketJSON(name: $0.name, creationDate: $0.creationDate) }
        return encode(items)
    }

    func formatObjects(_ objects: [S3Object], prefixes: [String]) -> String {
        var items: [ObjectJSON] = prefixes.map { ObjectJSON(key: $0, size: nil, lastModified: nil) }
        items += objects.map { ObjectJSON(key: $0.key, size: $0.size, lastModified: $0.lastModified) }
        return encode(items)
    }

    func formatError(_ error: any Error, verbose: Bool) -> String {
        if let s3Error = error as? S3APIError {
            let errorJSON = ErrorJSON(
                error: s3Error.message,
                code: verbose ? s3Error.code.rawValue : nil,
                resource: verbose ? s3Error.resource : nil,
                requestId: verbose ? s3Error.requestId : nil
            )
            return encode(errorJSON)
        }
        return encode(ErrorJSON(error: error.localizedDescription, code: nil, resource: nil, requestId: nil))
    }

    func formatSuccess(_ message: String) -> String {
        encode(["message": message])
    }

    private func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

private struct BucketJSON: Encodable {
    let name: String
    let creationDate: Date?
}

private struct ObjectJSON: Encodable {
    let key: String
    let size: Int64?
    let lastModified: Date?
}

private struct ErrorJSON: Encodable {
    let error: String
    let code: String?
    let resource: String?
    let requestId: String?
}
