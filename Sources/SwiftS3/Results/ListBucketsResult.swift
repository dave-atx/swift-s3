import Foundation

public struct ListBucketsResult: Sendable {
    public let buckets: [Bucket]
    public let owner: Owner?
    public let continuationToken: String?

    public init(buckets: [Bucket], owner: Owner?, continuationToken: String?) {
        self.buckets = buckets
        self.owner = owner
        self.continuationToken = continuationToken
    }
}
