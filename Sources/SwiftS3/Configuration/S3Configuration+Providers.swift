import Foundation

extension S3Configuration {
    public static func aws(
        accessKeyId: String,
        secretAccessKey: String,
        region: String
    ) -> S3Configuration {
        S3Configuration(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            region: region,
            endpoint: URL(string: "https://s3.\(region).amazonaws.com")!,
            usePathStyleAddressing: false
        )
    }

    public static func backblaze(
        accessKeyId: String,
        secretAccessKey: String,
        region: String
    ) -> S3Configuration {
        S3Configuration(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            region: region,
            endpoint: URL(string: "https://s3.\(region).backblazeb2.com")!,
            usePathStyleAddressing: true
        )
    }

    public static func cloudflare(
        accessKeyId: String,
        secretAccessKey: String,
        accountId: String
    ) -> S3Configuration {
        S3Configuration(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            region: "auto",
            endpoint: URL(string: "https://\(accountId).r2.cloudflarestorage.com")!,
            usePathStyleAddressing: true
        )
    }

    public static func gcs(
        accessKeyId: String,
        secretAccessKey: String
    ) -> S3Configuration {
        S3Configuration(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            region: "auto",
            endpoint: URL(string: "https://storage.googleapis.com")!,
            usePathStyleAddressing: true
        )
    }
}
