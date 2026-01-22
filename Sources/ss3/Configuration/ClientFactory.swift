import Foundation
import SwiftS3
import ArgumentParser

enum ClientFactory {
    static func createClient(from config: ResolvedConfiguration) throws -> S3Client {
        guard let keyId = config.keyId else {
            throw ValidationError("Missing key ID. Use --key-id or set SS3_KEY_ID")
        }
        guard let secretKey = config.secretKey else {
            throw ValidationError("Missing secret key. Use --secret-key or set SS3_SECRET_KEY")
        }
        guard let region = config.region else {
            throw ValidationError("Missing region. Use --region or set SS3_REGION")
        }
        guard let endpoint = config.endpoint else {
            throw ValidationError("Missing endpoint. Use --endpoint or set SS3_ENDPOINT")
        }
        guard let endpointURL = URL(string: endpoint) else {
            throw ValidationError("Invalid endpoint URL: \(endpoint)")
        }

        let s3Config = S3Configuration(
            accessKeyId: keyId,
            secretAccessKey: secretKey,
            region: region,
            endpoint: endpointURL
        )
        return S3Client(configuration: s3Config)
    }
}
