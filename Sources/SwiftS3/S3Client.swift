import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class S3Client: Sendable {
    private let configuration: S3Configuration
    private let httpClient: HTTPClient
    private let signer: SigV4Signer
    private let requestBuilder: RequestBuilder

    public init(configuration: S3Configuration) {
        self.configuration = configuration
        self.httpClient = HTTPClient()
        self.signer = SigV4Signer(
            accessKeyId: configuration.accessKeyId,
            secretAccessKey: configuration.secretAccessKey,
            region: configuration.region
        )
        self.requestBuilder = RequestBuilder(configuration: configuration)
    }

    // MARK: - Private Helpers

    private func executeRequest(_ request: URLRequest, body: Data?) async throws -> (Data, HTTPURLResponse) {
        var signedRequest = request
        let payloadHash = (body ?? Data()).sha256().hexString
        signer.sign(request: &signedRequest, date: Date(), payloadHash: payloadHash)

        let (data, response) = try await httpClient.execute(signedRequest)

        // Check for error responses
        if response.statusCode >= 400 {
            let error = try XMLResponseParser().parseError(from: data)
            throw error
        }

        return (data, response)
    }

    // MARK: - Bucket Operations

    public func listBuckets(
        prefix: String? = nil,
        maxBuckets: Int? = nil,
        continuationToken: String? = nil
    ) async throws -> ListBucketsResult {
        var queryItems: [URLQueryItem] = []
        if let prefix = prefix {
            queryItems.append(URLQueryItem(name: "prefix", value: prefix))
        }
        if let maxBuckets = maxBuckets {
            queryItems.append(URLQueryItem(name: "max-buckets", value: String(maxBuckets)))
        }
        if let continuationToken = continuationToken {
            queryItems.append(URLQueryItem(name: "continuation-token", value: continuationToken))
        }

        let request = requestBuilder.buildRequest(
            method: "GET",
            bucket: nil,
            key: nil,
            queryItems: queryItems.isEmpty ? nil : queryItems,
            headers: nil,
            body: nil
        )

        let (data, _) = try await executeRequest(request, body: nil)
        return try XMLResponseParser().parseListBuckets(from: data)
    }

    public func createBucket(_ name: String, region: String? = nil) async throws {
        var body: Data? = nil

        // If region differs from configuration region, include LocationConstraint
        if let region = region, region != configuration.region {
            let xml = """
                <?xml version="1.0" encoding="UTF-8"?>
                <CreateBucketConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <LocationConstraint>\(region)</LocationConstraint>
                </CreateBucketConfiguration>
                """
            body = xml.data(using: .utf8)
        }

        let request = requestBuilder.buildRequest(
            method: "PUT",
            bucket: name,
            key: nil,
            queryItems: nil,
            headers: body != nil ? ["Content-Type": "application/xml"] : nil,
            body: body
        )

        _ = try await executeRequest(request, body: body)
    }

    public func deleteBucket(_ name: String) async throws {
        let request = requestBuilder.buildRequest(
            method: "DELETE",
            bucket: name,
            key: nil,
            queryItems: nil,
            headers: nil,
            body: nil
        )

        _ = try await executeRequest(request, body: nil)
    }

    // MARK: - Object Operations

    public func listObjects(
        bucket: String,
        prefix: String? = nil,
        delimiter: String? = nil,
        maxKeys: Int? = nil,
        continuationToken: String? = nil
    ) async throws -> ListObjectsResult {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "list-type", value: "2")
        ]
        if let prefix = prefix {
            queryItems.append(URLQueryItem(name: "prefix", value: prefix))
        }
        if let delimiter = delimiter {
            queryItems.append(URLQueryItem(name: "delimiter", value: delimiter))
        }
        if let maxKeys = maxKeys {
            queryItems.append(URLQueryItem(name: "max-keys", value: String(maxKeys)))
        }
        if let continuationToken = continuationToken {
            queryItems.append(URLQueryItem(name: "continuation-token", value: continuationToken))
        }

        let request = requestBuilder.buildRequest(
            method: "GET",
            bucket: bucket,
            key: nil,
            queryItems: queryItems,
            headers: nil,
            body: nil
        )

        let (data, _) = try await executeRequest(request, body: nil)
        return try XMLResponseParser().parseListObjects(from: data)
    }

    public func getObject(
        bucket: String,
        key: String,
        range: Range<Int64>? = nil
    ) async throws -> (data: Data, metadata: ObjectMetadata) {
        var headers: [String: String] = [:]
        if let range = range {
            headers["Range"] = "bytes=\(range.lowerBound)-\(range.upperBound - 1)"
        }

        let request = requestBuilder.buildRequest(
            method: "GET",
            bucket: bucket,
            key: key,
            queryItems: nil,
            headers: headers.isEmpty ? nil : headers,
            body: nil
        )

        let (data, response) = try await executeRequest(request, body: nil)
        let metadata = parseObjectMetadata(from: response)

        return (data, metadata)
    }

    private func parseObjectMetadata(from response: HTTPURLResponse) -> ObjectMetadata {
        let contentLength = Int64(response.value(forHTTPHeaderField: "Content-Length") ?? "0") ?? 0

        var customMetadata: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let keyString = key as? String,
               keyString.lowercased().hasPrefix("x-amz-meta-") {
                let metaKey = String(keyString.dropFirst("x-amz-meta-".count))
                customMetadata[metaKey] = value as? String
            }
        }

        return ObjectMetadata(
            contentLength: contentLength,
            contentType: response.value(forHTTPHeaderField: "Content-Type"),
            etag: response.value(forHTTPHeaderField: "ETag"),
            lastModified: parseHTTPDate(response.value(forHTTPHeaderField: "Last-Modified")),
            versionId: response.value(forHTTPHeaderField: "x-amz-version-id"),
            metadata: customMetadata
        )
    }

    private func parseHTTPDate(_ string: String?) -> Date? {
        guard let string = string else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: string)
    }

    // TODO: Find cross-platform solution for streaming downloads on Linux.
    // See: https://github.com/dave-atx/swift-s3/issues/3
    #if !canImport(FoundationNetworking)
    public func getObjectStream(
        bucket: String,
        key: String,
        range: Range<Int64>? = nil
    ) async throws -> (stream: AsyncThrowingStream<UInt8, Error>, metadata: ObjectMetadata) {
        var headers: [String: String] = [:]
        if let range = range {
            headers["Range"] = "bytes=\(range.lowerBound)-\(range.upperBound - 1)"
        }

        var request = requestBuilder.buildRequest(
            method: "GET",
            bucket: bucket,
            key: key,
            queryItems: nil,
            headers: headers.isEmpty ? nil : headers,
            body: nil
        )

        let payloadHash = Data().sha256().hexString
        signer.sign(request: &request, date: Date(), payloadHash: payloadHash)

        let (bytes, response) = try await httpClient.executeStream(request)

        if response.statusCode >= 400 {
            // For error responses, we need to read the body
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            let error = try XMLResponseParser().parseError(from: errorData)
            throw error
        }

        let metadata = parseObjectMetadata(from: response)

        let stream = AsyncThrowingStream<UInt8, Error> { continuation in
            Task {
                do {
                    for try await byte in bytes {
                        continuation.yield(byte)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        return (stream, metadata)
    }
    #endif

    public func putObject(
        bucket: String,
        key: String,
        data: Data,
        contentType: String? = nil,
        metadata: [String: String]? = nil
    ) async throws -> String {
        var headers: [String: String] = [:]
        headers["Content-Length"] = String(data.count)

        if let contentType = contentType {
            headers["Content-Type"] = contentType
        }

        if let metadata = metadata {
            for (key, value) in metadata {
                headers["x-amz-meta-\(key)"] = value
            }
        }

        let request = requestBuilder.buildRequest(
            method: "PUT",
            bucket: bucket,
            key: key,
            queryItems: nil,
            headers: headers,
            body: data
        )

        let (_, response) = try await executeRequest(request, body: data)
        return response.value(forHTTPHeaderField: "ETag") ?? ""
    }

    public func deleteObject(bucket: String, key: String) async throws {
        let request = requestBuilder.buildRequest(
            method: "DELETE",
            bucket: bucket,
            key: key,
            queryItems: nil,
            headers: nil,
            body: nil
        )

        _ = try await executeRequest(request, body: nil)
    }

    public func headObject(bucket: String, key: String) async throws -> ObjectMetadata {
        let request = requestBuilder.buildRequest(
            method: "HEAD",
            bucket: bucket,
            key: key,
            queryItems: nil,
            headers: nil,
            body: nil
        )

        let (_, response) = try await executeRequest(request, body: nil)
        return parseObjectMetadata(from: response)
    }

    public func copyObject(
        sourceBucket: String,
        sourceKey: String,
        destinationBucket: String,
        destinationKey: String
    ) async throws -> String {
        let copySource = "/\(sourceBucket)/\(sourceKey)"

        let request = requestBuilder.buildRequest(
            method: "PUT",
            bucket: destinationBucket,
            key: destinationKey,
            queryItems: nil,
            headers: ["x-amz-copy-source": copySource],
            body: nil
        )

        let (_, response) = try await executeRequest(request, body: nil)
        return response.value(forHTTPHeaderField: "ETag") ?? ""
    }

    // MARK: - Multipart Upload Operations

    public func createMultipartUpload(
        bucket: String,
        key: String,
        contentType: String? = nil,
        metadata: [String: String]? = nil
    ) async throws -> MultipartUpload {
        var headers: [String: String] = [:]

        if let contentType = contentType {
            headers["Content-Type"] = contentType
        }

        if let metadata = metadata {
            for (key, value) in metadata {
                headers["x-amz-meta-\(key)"] = value
            }
        }

        let request = requestBuilder.buildRequest(
            method: "POST",
            bucket: bucket,
            key: key,
            queryItems: [URLQueryItem(name: "uploads", value: nil)],
            headers: headers.isEmpty ? nil : headers,
            body: nil
        )

        let (data, _) = try await executeRequest(request, body: nil)
        return try XMLResponseParser().parseInitiateMultipartUpload(from: data)
    }

    public func uploadPart(
        bucket: String,
        key: String,
        uploadId: String,
        partNumber: Int,
        data: Data
    ) async throws -> CompletedPart {
        let request = requestBuilder.buildRequest(
            method: "PUT",
            bucket: bucket,
            key: key,
            queryItems: [
                URLQueryItem(name: "partNumber", value: String(partNumber)),
                URLQueryItem(name: "uploadId", value: uploadId)
            ],
            headers: ["Content-Length": String(data.count)],
            body: data
        )

        let (_, response) = try await executeRequest(request, body: data)
        let etag = response.value(forHTTPHeaderField: "ETag") ?? ""

        return CompletedPart(partNumber: partNumber, etag: etag)
    }

    public func completeMultipartUpload(
        bucket: String,
        key: String,
        uploadId: String,
        parts: [CompletedPart]
    ) async throws -> String {
        let sortedParts = parts.sorted { $0.partNumber < $1.partNumber }

        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<CompleteMultipartUpload>"
        for part in sortedParts {
            xml += "<Part><PartNumber>\(part.partNumber)</PartNumber><ETag>\(part.etag)</ETag></Part>"
        }
        xml += "</CompleteMultipartUpload>"

        let body = xml.data(using: .utf8)!

        let request = requestBuilder.buildRequest(
            method: "POST",
            bucket: bucket,
            key: key,
            queryItems: [URLQueryItem(name: "uploadId", value: uploadId)],
            headers: ["Content-Type": "application/xml"],
            body: body
        )

        let (_, response) = try await executeRequest(request, body: body)
        return response.value(forHTTPHeaderField: "ETag") ?? ""
    }

    public func abortMultipartUpload(
        bucket: String,
        key: String,
        uploadId: String
    ) async throws {
        let request = requestBuilder.buildRequest(
            method: "DELETE",
            bucket: bucket,
            key: key,
            queryItems: [URLQueryItem(name: "uploadId", value: uploadId)],
            headers: nil,
            body: nil
        )

        _ = try await executeRequest(request, body: nil)
    }

    public func listMultipartUploads(
        bucket: String,
        prefix: String? = nil,
        maxUploads: Int? = nil
    ) async throws -> ListMultipartUploadsResult {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "uploads", value: nil)
        ]
        if let prefix = prefix {
            queryItems.append(URLQueryItem(name: "prefix", value: prefix))
        }
        if let maxUploads = maxUploads {
            queryItems.append(URLQueryItem(name: "max-uploads", value: String(maxUploads)))
        }

        let request = requestBuilder.buildRequest(
            method: "GET",
            bucket: bucket,
            key: nil,
            queryItems: queryItems,
            headers: nil,
            body: nil
        )

        let (data, _) = try await executeRequest(request, body: nil)
        return try XMLResponseParser().parseListMultipartUploads(from: data)
    }

    public func listParts(
        bucket: String,
        key: String,
        uploadId: String,
        maxParts: Int? = nil,
        partNumberMarker: Int? = nil
    ) async throws -> ListPartsResult {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "uploadId", value: uploadId)
        ]
        if let maxParts = maxParts {
            queryItems.append(URLQueryItem(name: "max-parts", value: String(maxParts)))
        }
        if let partNumberMarker = partNumberMarker {
            queryItems.append(URLQueryItem(name: "part-number-marker", value: String(partNumberMarker)))
        }

        let request = requestBuilder.buildRequest(
            method: "GET",
            bucket: bucket,
            key: key,
            queryItems: queryItems,
            headers: nil,
            body: nil
        )

        let (data, _) = try await executeRequest(request, body: nil)
        return try XMLResponseParser().parseListParts(from: data)
    }
}
