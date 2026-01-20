import Foundation

public struct S3APIError: S3Error {
    public let code: Code
    public let message: String
    public let resource: String?
    public let requestId: String?

    public init(code: Code, message: String, resource: String?, requestId: String?) {
        self.code = code
        self.message = message
        self.resource = resource
        self.requestId = requestId
    }

    public enum Code: Sendable, Equatable {
        case accessDenied
        case bucketAlreadyExists
        case bucketNotEmpty
        case invalidBucketName
        case noSuchBucket
        case noSuchKey
        case noSuchUpload
        case preconditionFailed
        case invalidRequest
        case invalidPart
        case invalidPartOrder
        case unknown(String)

        public var rawValue: String {
            switch self {
            case .accessDenied: return "AccessDenied"
            case .bucketAlreadyExists: return "BucketAlreadyExists"
            case .bucketNotEmpty: return "BucketNotEmpty"
            case .invalidBucketName: return "InvalidBucketName"
            case .noSuchBucket: return "NoSuchBucket"
            case .noSuchKey: return "NoSuchKey"
            case .noSuchUpload: return "NoSuchUpload"
            case .preconditionFailed: return "PreconditionFailed"
            case .invalidRequest: return "InvalidRequest"
            case .invalidPart: return "InvalidPart"
            case .invalidPartOrder: return "InvalidPartOrder"
            case .unknown(let code): return code
            }
        }

        public init(rawValue: String) {
            switch rawValue {
            case "AccessDenied": self = .accessDenied
            case "BucketAlreadyExists": self = .bucketAlreadyExists
            case "BucketNotEmpty": self = .bucketNotEmpty
            case "InvalidBucketName": self = .invalidBucketName
            case "NoSuchBucket": self = .noSuchBucket
            case "NoSuchKey": self = .noSuchKey
            case "NoSuchUpload": self = .noSuchUpload
            case "PreconditionFailed": self = .preconditionFailed
            case "InvalidRequest": self = .invalidRequest
            case "InvalidPart": self = .invalidPart
            case "InvalidPartOrder": self = .invalidPartOrder
            default: self = .unknown(rawValue)
            }
        }
    }
}
