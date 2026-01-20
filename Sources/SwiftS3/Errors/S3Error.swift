import Foundation

public protocol S3Error: Error, Sendable {
    var message: String { get }
}
