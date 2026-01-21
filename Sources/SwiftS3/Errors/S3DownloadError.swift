import Foundation

public struct S3DownloadError: S3Error, Sendable {
    public let message: String
    public let resumeData: Data?
    public let underlyingError: (any Error)?

    public init(message: String, resumeData: Data?, underlyingError: (any Error)?) {
        self.message = message
        self.resumeData = resumeData
        self.underlyingError = underlyingError
    }
}
