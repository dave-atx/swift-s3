import Foundation

public struct ListMultipartUploadsResult: Sendable {
    public let uploads: [MultipartUpload]
    public let isTruncated: Bool
    public let nextKeyMarker: String?
    public let nextUploadIdMarker: String?

    public init(uploads: [MultipartUpload], isTruncated: Bool, nextKeyMarker: String?, nextUploadIdMarker: String?) {
        self.uploads = uploads
        self.isTruncated = isTruncated
        self.nextKeyMarker = nextKeyMarker
        self.nextUploadIdMarker = nextUploadIdMarker
    }
}
