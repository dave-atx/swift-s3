import Foundation
import SwiftS3

enum ClientFactory {
    static func createClient(from profile: ResolvedProfile) -> S3Client {
        let config = S3Configuration(
            accessKeyId: profile.accessKeyId,
            secretAccessKey: profile.secretAccessKey,
            region: profile.region,
            endpoint: profile.endpoint,
            usePathStyleAddressing: profile.pathStyle
        )
        return S3Client(configuration: config)
    }
}
