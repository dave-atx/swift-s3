import Testing
@testable import ss3

@Test func s3PathParsesValidTouchTarget() {
    let path = S3Path.parse("e2:mybucket/newfile.txt")
    guard case .remote(let profile, let bucket, let key) = path else {
        Issue.record("Expected remote path")
        return
    }
    #expect(profile == "e2")
    #expect(bucket == "mybucket")
    #expect(key == "newfile.txt")
    #expect(key?.hasSuffix("/") == false)
}

@Test func s3PathParsesNestedTouchTarget() {
    let path = S3Path.parse("e2:mybucket/deep/nested/file.txt")
    guard case .remote(_, let bucket, let key) = path else {
        Issue.record("Expected remote path")
        return
    }
    #expect(bucket == "mybucket")
    #expect(key == "deep/nested/file.txt")
}
