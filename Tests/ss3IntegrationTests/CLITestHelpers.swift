import Foundation
import SwiftS3

/// Shared utilities for CLI integration tests.
/// Reuses MinioTestServer from IntegrationTests.
enum CLITestConfig {
    static var s3Configuration: S3Configuration {
        S3Configuration(
            accessKeyId: MinioTestServer.accessKey,
            secretAccessKey: MinioTestServer.secretKey,
            region: "us-east-1",
            endpoint: MinioTestServer.endpointURL,
            usePathStyleAddressing: true
        )
    }

    static func createClient() -> S3Client {
        S3Client(configuration: s3Configuration)
    }

    static func uniqueBucketName(prefix: String = "cli") -> String {
        let uuid = UUID().uuidString.prefix(8).lowercased()
        return "\(prefix)-\(uuid)"
    }
}

/// Cleans up a bucket via the library (not CLI) for reliability.
func cleanupBucketViaCLI(_ bucketName: String) async {
    let client = CLITestConfig.createClient()
    do {
        let result = try await client.listObjects(bucket: bucketName)
        for object in result.objects {
            try? await client.deleteObject(bucket: bucketName, key: object.key)
        }
        try await client.deleteBucket(bucketName)
    } catch {
        // Ignore cleanup errors
    }
}
