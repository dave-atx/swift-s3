import Foundation

extension S3Configuration {
    public static func aws(
        accessKeyId: String,
        secretAccessKey: String,
        region: String
    ) -> S3Configuration {
        guard let endpoint = URL(string: "https://s3.\(region).amazonaws.com") else {
            fatalError("Invalid AWS region for URL: \(region)")
        }
        return S3Configuration(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            region: region,
            endpoint: endpoint,
            usePathStyleAddressing: false
        )
    }

    public static func backblaze(
        accessKeyId: String,
        secretAccessKey: String,
        region: String
    ) -> S3Configuration {
        guard let endpoint = URL(string: "https://s3.\(region).backblazeb2.com") else {
            fatalError("Invalid Backblaze region for URL: \(region)")
        }
        return S3Configuration(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            region: region,
            endpoint: endpoint,
            usePathStyleAddressing: true
        )
    }

    public static func cloudflare(
        accessKeyId: String,
        secretAccessKey: String,
        accountId: String
    ) -> S3Configuration {
        guard let endpoint = URL(string: "https://\(accountId).r2.cloudflarestorage.com") else {
            fatalError("Invalid Cloudflare account ID for URL: \(accountId)")
        }
        return S3Configuration(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            region: "auto",
            endpoint: endpoint,
            usePathStyleAddressing: true
        )
    }

    public static func gcs(
        accessKeyId: String,
        secretAccessKey: String
    ) -> S3Configuration {
        guard let endpoint = URL(string: "https://storage.googleapis.com") else {
            fatalError("Invalid GCS endpoint URL")
        }
        return S3Configuration(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            region: "auto",
            endpoint: endpoint,
            usePathStyleAddressing: true
        )
    }
}
