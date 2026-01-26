enum S3Path: Equatable, Sendable {
    case local(String)
    case remote(profile: String, bucket: String?, key: String?)

    var isLocal: Bool {
        if case .local = self { return true }
        return false
    }

    var isRemote: Bool {
        if case .remote = self { return true }
        return false
    }

    var profile: String? {
        if case .remote(let profile, _, _) = self { return profile }
        return nil
    }

    static func parse(_ path: String) -> S3Path {
        // Colon is the discriminator - if present, it's a profile path
        guard let colonIndex = path.firstIndex(of: ":") else {
            // No colon = local path
            return .local(path)
        }

        let profile = String(path[..<colonIndex])
        let remainder = String(path[path.index(after: colonIndex)...])

        // Handle list buckets cases: "e2:" or "e2:/" or "e2:."
        if remainder.isEmpty || remainder == "/" || remainder == "." {
            return .remote(profile: profile, bucket: nil, key: nil)
        }

        // Parse bucket/key from remainder
        let components = remainder.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let bucket = String(components[0])

        if components.count == 1 {
            // Just bucket, no slash after
            return .remote(profile: profile, bucket: bucket, key: nil)
        }

        // Has slash - check what's after
        let keyPart = String(components[1])
        if keyPart.isEmpty {
            // Trailing slash only: "e2:bucket/"
            return .remote(profile: profile, bucket: bucket, key: nil)
        }

        return .remote(profile: profile, bucket: bucket, key: keyPart)
    }
}
