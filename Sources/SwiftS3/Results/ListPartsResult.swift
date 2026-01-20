import Foundation

public struct ListPartsResult: Sendable {
    public let parts: [Part]
    public let isTruncated: Bool
    public let nextPartNumberMarker: Int?

    public init(parts: [Part], isTruncated: Bool, nextPartNumberMarker: Int?) {
        self.parts = parts
        self.isTruncated = isTruncated
        self.nextPartNumberMarker = nextPartNumberMarker
    }
}
