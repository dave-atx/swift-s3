import Foundation

public struct ObjectMetadata: Sendable {
    public let contentLength: Int64
    public let contentType: String?
    public let etag: String?
    public let lastModified: Date?
    public let versionId: String?
    public let metadata: [String: String]

    public init(
        contentLength: Int64,
        contentType: String?,
        etag: String?,
        lastModified: Date?,
        versionId: String?,
        metadata: [String: String]
    ) {
        self.contentLength = contentLength
        self.contentType = contentType
        self.etag = etag
        self.lastModified = lastModified
        self.versionId = versionId
        self.metadata = metadata
    }
}
