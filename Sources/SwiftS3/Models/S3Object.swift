import Foundation

public struct S3Object: Sendable, Equatable {
    public let key: String
    public let lastModified: Date?
    public let etag: String?
    public let size: Int64?
    public let storageClass: String?
    public let owner: Owner?

    public init(
        key: String,
        lastModified: Date?,
        etag: String?,
        size: Int64?,
        storageClass: String?,
        owner: Owner?
    ) {
        self.key = key
        self.lastModified = lastModified
        self.etag = etag
        self.size = size
        self.storageClass = storageClass
        self.owner = owner
    }
}
