import Foundation

public struct S3NetworkError: S3Error {
    public let message: String
    public let underlyingError: (any Error)?

    public init(message: String, underlyingError: (any Error)?) {
        self.message = message
        self.underlyingError = underlyingError
    }
}
