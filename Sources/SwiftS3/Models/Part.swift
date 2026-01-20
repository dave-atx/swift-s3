import Foundation

public struct Part: Sendable {
    public let partNumber: Int
    public let etag: String
    public let size: Int64?
    public let lastModified: Date?

    public init(partNumber: Int, etag: String, size: Int64?, lastModified: Date?) {
        self.partNumber = partNumber
        self.etag = etag
        self.size = size
        self.lastModified = lastModified
    }
}
