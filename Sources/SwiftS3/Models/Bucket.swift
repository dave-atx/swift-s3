import Foundation

public struct Bucket: Sendable, Equatable {
    public let name: String
    public let creationDate: Date?
    public let region: String?

    public init(name: String, creationDate: Date?, region: String?) {
        self.name = name
        self.creationDate = creationDate
        self.region = region
    }
}
