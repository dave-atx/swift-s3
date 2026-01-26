import Testing
@testable import ss3

// Local path tests
@Test func s3PathParsesAbsoluteLocal() {
    let path = S3Path.parse("/home/user/file.txt")
    #expect(path == .local("/home/user/file.txt"))
}

@Test func s3PathParsesRelativeLocal() {
    let path = S3Path.parse("./file.txt")
    #expect(path == .local("./file.txt"))
}

@Test func s3PathParsesParentRelativeLocal() {
    let path = S3Path.parse("../file.txt")
    #expect(path == .local("../file.txt"))
}

@Test func s3PathParsesSimpleFilenameAsLocal() {
    // No colon = local path
    let path = S3Path.parse("file.txt")
    #expect(path == .local("file.txt"))
}

// Remote path tests - profile:bucket/key format
@Test func s3PathParsesProfileListBuckets() {
    // e2: or e2:/ or e2:. all mean list buckets
    #expect(S3Path.parse("e2:") == .remote(profile: "e2", bucket: nil, key: nil))
    #expect(S3Path.parse("e2:/") == .remote(profile: "e2", bucket: nil, key: nil))
    #expect(S3Path.parse("e2:.") == .remote(profile: "e2", bucket: nil, key: nil))
}

@Test func s3PathParsesProfileBucketOnly() {
    let path = S3Path.parse("e2:mybucket")
    #expect(path == .remote(profile: "e2", bucket: "mybucket", key: nil))
}

@Test func s3PathParsesProfileBucketWithTrailingSlash() {
    let path = S3Path.parse("e2:mybucket/")
    #expect(path == .remote(profile: "e2", bucket: "mybucket", key: nil))
}

@Test func s3PathParsesProfileBucketAndKey() {
    let path = S3Path.parse("e2:mybucket/path/to/file.txt")
    #expect(path == .remote(profile: "e2", bucket: "mybucket", key: "path/to/file.txt"))
}

@Test func s3PathParsesProfileBucketAndKeyWithSlash() {
    let path = S3Path.parse("e2:mybucket/dir/")
    #expect(path == .remote(profile: "e2", bucket: "mybucket", key: "dir/"))
}

// Convenience properties
@Test func s3PathIsLocal() {
    #expect(S3Path.local("/file.txt").isLocal)
    #expect(S3Path.local("file.txt").isLocal)
    #expect(!S3Path.remote(profile: "e2", bucket: "b", key: "k").isLocal)
}

@Test func s3PathIsRemote() {
    #expect(!S3Path.local("/file.txt").isRemote)
    #expect(S3Path.remote(profile: "e2", bucket: "b", key: "k").isRemote)
}

@Test func s3PathProfileName() {
    #expect(S3Path.local("/file.txt").profile == nil)
    #expect(S3Path.remote(profile: "e2", bucket: "b", key: "k").profile == "e2")
}
