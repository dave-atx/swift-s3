import Foundation
import SwiftS3

/// Shared test configuration and utilities for integration tests.
enum TestConfig {
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

    /// Generates a unique bucket name for test isolation.
    static func uniqueBucketName(prefix: String = "test") -> String {
        let uuid = UUID().uuidString.prefix(8).lowercased()
        return "\(prefix)-\(uuid)"
    }
}

/// Cleans up a bucket by deleting all objects then the bucket itself.
/// Silently ignores errors to avoid masking test failures.
func cleanupBucket(_ client: S3Client, _ bucketName: String) async {
    do {
        // List and delete all objects
        let result = try await client.listObjects(bucket: bucketName)
        for object in result.objects {
            try? await client.deleteObject(bucket: bucketName, key: object.key)
        }

        // Delete the bucket
        try await client.deleteBucket(bucketName)
    } catch {
        // Ignore cleanup errors
    }
}

/// Generates random data of specified size for testing.
func randomData(size: Int) -> Data {
    var data = Data(count: size)
    for idx in 0..<size {
        data[idx] = UInt8.random(in: 0...255)
    }
    return data
}
