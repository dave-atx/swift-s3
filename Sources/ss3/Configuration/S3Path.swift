enum S3Path: Equatable, Sendable {
    case local(String)
    case remote(bucket: String, key: String?)

    var isLocal: Bool {
        if case .local = self { return true }
        return false
    }

    var isRemote: Bool {
        if case .remote = self { return true }
        return false
    }

    static func parse(_ path: String, defaultBucket: String? = nil) -> S3Path {
        // Absolute paths are always local
        if path.hasPrefix("/") {
            return .local(path)
        }

        // Relative paths starting with ./ or ../ are local
        if path.hasPrefix("./") || path.hasPrefix("../") {
            return .local(path)
        }

        // If we have a default bucket and path doesn't look like bucket/key
        if let bucket = defaultBucket {
            return .remote(bucket: bucket, key: path)
        }

        // Parse as bucket/key
        let components = path.split(separator: "/", maxSplits: 1)
        let bucket = String(components[0])

        if components.count == 1 {
            // Just bucket name, possibly with trailing slash
            return .remote(bucket: bucket, key: nil)
        }

        let key = String(components[1])
        return .remote(bucket: bucket, key: key.isEmpty ? nil : key)
    }
}
