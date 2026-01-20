import Foundation

public struct ListObjectsResult: Sendable {
    public let name: String
    public let prefix: String?
    public let objects: [S3Object]
    public let commonPrefixes: [String]
    public let isTruncated: Bool
    public let continuationToken: String?

    public init(name: String, prefix: String?, objects: [S3Object], commonPrefixes: [String], isTruncated: Bool, continuationToken: String?) {
        self.name = name
        self.prefix = prefix
        self.objects = objects
        self.commonPrefixes = commonPrefixes
        self.isTruncated = isTruncated
        self.continuationToken = continuationToken
    }
}
