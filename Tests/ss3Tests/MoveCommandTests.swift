import Testing
@testable import ss3

@Test func s3PathParsesValidMoveSource() {
    let path = S3Path.parse("e2:mybucket/source.txt")
    guard case .remote(let profile, let bucket, let key) = path else {
        Issue.record("Expected remote path")
        return
    }
    #expect(profile == "e2")
    #expect(bucket == "mybucket")
    #expect(key == "source.txt")
}

@Test func s3PathParsesValidMoveDestination() {
    let path = S3Path.parse("e2:mybucket/dest.txt")
    guard case .remote(let profile, let bucket, let key) = path else {
        Issue.record("Expected remote path")
        return
    }
    #expect(profile == "e2")
    #expect(bucket == "mybucket")
    #expect(key == "dest.txt")
}

@Test func s3PathParsesCrossBucketMove() {
    let src = S3Path.parse("e2:bucket1/file.txt")
    let dst = S3Path.parse("e2:bucket2/file.txt")

    guard case .remote(let srcProfile, let srcBucket, _) = src,
          case .remote(let dstProfile, let dstBucket, _) = dst else {
        Issue.record("Expected remote paths")
        return
    }

    #expect(srcProfile == dstProfile)  // Same profile required
    #expect(srcBucket == "bucket1")
    #expect(dstBucket == "bucket2")
}
