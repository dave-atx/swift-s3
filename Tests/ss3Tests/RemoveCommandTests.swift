import Testing
@testable import ss3

@Test func s3PathRejectsDirectoryPath() {
    let path = S3Path.parse("e2:mybucket/dir/")
    guard case .remote(_, _, let key) = path else {
        Issue.record("Expected remote path")
        return
    }
    // rm command should reject paths ending with /
    #expect(key?.hasSuffix("/") == true)
}

@Test func s3PathRequiresKeyForRemove() {
    let bucketOnly = S3Path.parse("e2:mybucket")
    guard case .remote(_, let bucket, let key) = bucketOnly else {
        Issue.record("Expected remote path")
        return
    }
    #expect(bucket == "mybucket")
    #expect(key == nil)  // rm requires key to be non-nil
}

@Test func s3PathParsesValidRemoveTarget() {
    let path = S3Path.parse("e2:mybucket/path/to/file.txt")
    guard case .remote(let profile, let bucket, let key) = path else {
        Issue.record("Expected remote path")
        return
    }
    #expect(profile == "e2")
    #expect(bucket == "mybucket")
    #expect(key == "path/to/file.txt")
    #expect(key?.hasSuffix("/") == false)
}
