import Testing
import Foundation
@testable import ss3

@Test func chunkCalculationForSmallFile() {
    let chunks = MultipartUploader.calculateChunks(fileSize: 1000, chunkSize: 500)
    #expect(chunks.count == 2)
    #expect(chunks[0].partNumber == 1)
    #expect(chunks[0].offset == 0)
    #expect(chunks[0].length == 500)
    #expect(chunks[1].partNumber == 2)
    #expect(chunks[1].offset == 500)
    #expect(chunks[1].length == 500)
}

@Test func chunkCalculationWithRemainder() {
    let chunks = MultipartUploader.calculateChunks(fileSize: 1100, chunkSize: 500)
    #expect(chunks.count == 3)
    #expect(chunks[2].length == 100)
}

@Test func chunkCalculationSingleChunk() {
    let chunks = MultipartUploader.calculateChunks(fileSize: 100, chunkSize: 500)
    #expect(chunks.count == 1)
    #expect(chunks[0].length == 100)
}
