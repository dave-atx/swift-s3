import Testing
@testable import ss3

@Test func s3PathParsesLocalFile() {
    let path = S3Path.parse("/home/user/file.txt")
    #expect(path == .local("/home/user/file.txt"))
}

@Test func s3PathParsesRelativeLocal() {
    let path = S3Path.parse("./file.txt")
    #expect(path == .local("./file.txt"))
}

@Test func s3PathParsesCurrentDirLocal() {
    let path = S3Path.parse("file.txt")
    // Single component without slash is ambiguous - treat as remote bucket
    #expect(path == .remote(bucket: "file.txt", key: nil))
}

@Test func s3PathParsesRemoteBucket() {
    let path = S3Path.parse("mybucket/")
    #expect(path == .remote(bucket: "mybucket", key: nil))
}

@Test func s3PathParsesRemoteKey() {
    let path = S3Path.parse("mybucket/path/to/file.txt")
    #expect(path == .remote(bucket: "mybucket", key: "path/to/file.txt"))
}

@Test func s3PathParsesRemoteWithBucketOption() {
    let path = S3Path.parse("path/to/file.txt", defaultBucket: "mybucket")
    #expect(path == .remote(bucket: "mybucket", key: "path/to/file.txt"))
}

@Test func s3PathIsLocal() {
    #expect(S3Path.local("/file.txt").isLocal)
    #expect(!S3Path.remote(bucket: "b", key: "k").isLocal)
}

@Test func s3PathIsRemote() {
    #expect(!S3Path.local("/file.txt").isRemote)
    #expect(S3Path.remote(bucket: "b", key: "k").isRemote)
}
