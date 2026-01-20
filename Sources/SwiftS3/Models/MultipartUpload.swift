import Foundation

public struct MultipartUpload: Sendable {
    public let uploadId: String
    public let key: String
    public let initiated: Date?

    public init(uploadId: String, key: String, initiated: Date?) {
        self.uploadId = uploadId
        self.key = key
        self.initiated = initiated
    }
}
