import Foundation

public struct S3Configuration: Sendable {
    public let accessKeyId: String
    public let secretAccessKey: String
    public let region: String
    public let endpoint: URL
    public let usePathStyleAddressing: Bool

    public init(
        accessKeyId: String,
        secretAccessKey: String,
        region: String,
        endpoint: URL,
        usePathStyleAddressing: Bool = false
    ) {
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.region = region
        self.endpoint = endpoint
        self.usePathStyleAddressing = usePathStyleAddressing
    }
}
