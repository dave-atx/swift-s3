import Foundation

public struct S3ParsingError: S3Error {
    public let message: String
    public let responseBody: String?

    public init(message: String, responseBody: String?) {
        self.message = message
        self.responseBody = responseBody
    }
}
