import Foundation
import SwiftS3

struct ChunkInfo: Sendable {
    let partNumber: Int
    let offset: Int64
    let length: Int64
}

struct MultipartUploader: Sendable {
    let client: S3Client
    let chunkSize: Int64
    let maxParallel: Int

    static func calculateChunks(fileSize: Int64, chunkSize: Int64) -> [ChunkInfo] {
        var chunks: [ChunkInfo] = []
        var offset: Int64 = 0
        var partNumber = 1

        while offset < fileSize {
            let remaining = fileSize - offset
            let length = min(chunkSize, remaining)
            chunks.append(ChunkInfo(partNumber: partNumber, offset: offset, length: length))
            offset += length
            partNumber += 1
        }

        return chunks
    }

    func upload(bucket: String, key: String, fileURL: URL, fileSize: Int64) async throws {
        let upload = try await client.createMultipartUpload(bucket: bucket, key: key)

        do {
            let parts = try await uploadParts(bucket: bucket, key: key, uploadId: upload.uploadId,
                                              fileURL: fileURL, fileSize: fileSize)
            _ = try await client.completeMultipartUpload(bucket: bucket, key: key,
                                                         uploadId: upload.uploadId, parts: parts)
        } catch {
            try? await client.abortMultipartUpload(bucket: bucket, key: key, uploadId: upload.uploadId)
            throw error
        }
    }

    private func uploadParts(
        bucket: String, key: String, uploadId: String, fileURL: URL, fileSize: Int64
    ) async throws -> [CompletedPart] {
        let chunks = Self.calculateChunks(fileSize: fileSize, chunkSize: chunkSize)
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }

        return try await withThrowingTaskGroup(of: CompletedPart.self) { group in
            var pending = chunks.makeIterator()
            var results: [CompletedPart] = []

            // Seed initial batch
            for _ in 0..<maxParallel {
                guard let chunk = pending.next() else { break }
                let chunkData = try readChunk(fileHandle: fileHandle, chunk: chunk)
                group.addTask { try await self.uploadChunk(bucket: bucket, key: key, uploadId: uploadId,
                                                           partNumber: chunk.partNumber, data: chunkData) }
            }

            // Process completions and add more
            for try await part in group {
                results.append(part)
                if let chunk = pending.next() {
                    let chunkData = try readChunk(fileHandle: fileHandle, chunk: chunk)
                    group.addTask { try await self.uploadChunk(bucket: bucket, key: key, uploadId: uploadId,
                                                               partNumber: chunk.partNumber, data: chunkData) }
                }
            }

            return results
        }
    }

    private func uploadChunk(bucket: String, key: String, uploadId: String,
                             partNumber: Int, data: Data) async throws -> CompletedPart {
        try await client.uploadPart(bucket: bucket, key: key, uploadId: uploadId, partNumber: partNumber, data: data)
    }

    private func readChunk(fileHandle: FileHandle, chunk: ChunkInfo) throws -> Data {
        try fileHandle.seek(toOffset: UInt64(chunk.offset))
        guard let data = try fileHandle.read(upToCount: Int(chunk.length)) else {
            throw MultipartError.readFailed
        }
        return data
    }
}

enum MultipartError: Error, LocalizedError {
    case readFailed

    var errorDescription: String? {
        switch self {
        case .readFailed: return "Failed to read chunk from file"
        }
    }
}
