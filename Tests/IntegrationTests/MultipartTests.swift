import Testing
import Foundation
@testable import SwiftS3

@Suite("Multipart Upload Operations", .serialized)
struct MultipartTests {
    init() async throws {
        try await MinioTestServer.shared.ensureRunning()
    }

    @Test
    func fullMultipartUploadFlow() async throws {
        try await withTestBucket(prefix: "multi") { client, bucket in
            let key = "multipart-test.bin"

            // Create multipart upload
            let upload = try await client.createMultipartUpload(bucket: bucket, key: key)
            #expect(!upload.uploadId.isEmpty)
            #expect(upload.key == key)

            // Upload two parts - minimum part size for S3/minio is 5MB
            let partSize = 5 * 1024 * 1024  // 5MB
            let part1Data = Data(repeating: 0x41, count: partSize)
            let part2Data = Data(repeating: 0x42, count: partSize)

            let completedPart1 = try await client.uploadPart(
                bucket: bucket,
                key: key,
                uploadId: upload.uploadId,
                partNumber: 1,
                data: part1Data
            )
            #expect(completedPart1.partNumber == 1)
            #expect(!completedPart1.etag.isEmpty)

            let completedPart2 = try await client.uploadPart(
                bucket: bucket,
                key: key,
                uploadId: upload.uploadId,
                partNumber: 2,
                data: part2Data
            )
            #expect(completedPart2.partNumber == 2)

            // Complete the upload
            let etag = try await client.completeMultipartUpload(
                bucket: bucket,
                key: key,
                uploadId: upload.uploadId,
                parts: [completedPart1, completedPart2]
            )
            #expect(!etag.isEmpty)

            // Verify the complete object
            let (data, metadata) = try await client.getObject(bucket: bucket, key: key)
            #expect(data == part1Data + part2Data)
            #expect(metadata.contentLength == Int64(part1Data.count + part2Data.count))
        }
    }

    @Test
    func abortMultipartUpload() async throws {
        try await withTestBucket(prefix: "abort") { client, bucket in
            let key = "abort-test.bin"

            // Create multipart upload
            let upload = try await client.createMultipartUpload(bucket: bucket, key: key)

            // Upload one part
            _ = try await client.uploadPart(
                bucket: bucket,
                key: key,
                uploadId: upload.uploadId,
                partNumber: 1,
                data: randomData(size: 512)
            )

            // Abort the upload
            try await client.abortMultipartUpload(bucket: bucket, key: key, uploadId: upload.uploadId)

            // Verify no incomplete uploads remain
            let uploads = try await client.listMultipartUploads(bucket: bucket)
            #expect(!uploads.uploads.contains { $0.uploadId == upload.uploadId })
        }
    }

    @Test
    func listParts() async throws {
        try await withTestBucket(prefix: "parts") { client, bucket in
            let key = "list-parts-test.bin"

            // Create multipart upload
            let upload = try await client.createMultipartUpload(bucket: bucket, key: key)

            do {
                // Upload three parts
                for partNum in 1...3 {
                    _ = try await client.uploadPart(
                        bucket: bucket,
                        key: key,
                        uploadId: upload.uploadId,
                        partNumber: partNum,
                        data: randomData(size: 256)
                    )
                }

                // List parts
                let partsResult = try await client.listParts(bucket: bucket, key: key, uploadId: upload.uploadId)
                #expect(partsResult.parts.count == 3)
                #expect(partsResult.parts.map(\.partNumber).sorted() == [1, 2, 3])
            } catch {
                try? await client.abortMultipartUpload(bucket: bucket, key: key, uploadId: upload.uploadId)
                throw error
            }

            try? await client.abortMultipartUpload(bucket: bucket, key: key, uploadId: upload.uploadId)
        }
    }

    @Test
    func listMultipartUploads() async throws {
        try await withTestBucket(prefix: "listuploads") { client, bucket in
            // Create multiple incomplete uploads
            let upload1 = try await client.createMultipartUpload(bucket: bucket, key: "upload1.bin")
            let upload2 = try await client.createMultipartUpload(bucket: bucket, key: "upload2.bin")

            do {
                // List multipart uploads
                let result = try await client.listMultipartUploads(bucket: bucket)
                #expect(result.uploads.count >= 2)
                #expect(result.uploads.contains { $0.key == "upload1.bin" })
                #expect(result.uploads.contains { $0.key == "upload2.bin" })
            } catch {
                try? await client.abortMultipartUpload(bucket: bucket, key: "upload1.bin", uploadId: upload1.uploadId)
                try? await client.abortMultipartUpload(bucket: bucket, key: "upload2.bin", uploadId: upload2.uploadId)
                throw error
            }

            try? await client.abortMultipartUpload(bucket: bucket, key: "upload1.bin", uploadId: upload1.uploadId)
            try? await client.abortMultipartUpload(bucket: bucket, key: "upload2.bin", uploadId: upload2.uploadId)
        }
    }
}
