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
func cleanupBucket(_ bucketName: String) async {
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

/// Runs a test with a bucket, ensuring cleanup is awaited before returning.
/// This prevents race conditions from fire-and-forget cleanup tasks.
func withTestBucket(
    prefix: String,
    test: (S3Client, String) async throws -> Void
) async throws {
    let client = CLITestConfig.createClient()
    let bucket = CLITestConfig.uniqueBucketName(prefix: prefix)
    try await client.createBucket(bucket)
    do {
        try await test(client, bucket)
        await cleanupBucket(bucket)
    } catch {
        await cleanupBucket(bucket)
        throw error
    }
}
