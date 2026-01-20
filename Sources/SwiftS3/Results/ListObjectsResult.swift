import Foundation

public struct ListObjectsResult: Sendable {
    public let objects: [S3Object]
    public let commonPrefixes: [String]
    public let isTruncated: Bool
    public let continuationToken: String?

    public init(objects: [S3Object], commonPrefixes: [String], isTruncated: Bool, continuationToken: String?) {
        self.objects = objects
        self.commonPrefixes = commonPrefixes
        self.isTruncated = isTruncated
        self.continuationToken = continuationToken
    }
}
