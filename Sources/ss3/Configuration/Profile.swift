import Foundation

enum ProfileError: Error, CustomStringConvertible {
    case invalidURL(String)
    case missingCredentials(profile: String)

    var description: String {
        switch self {
        case .invalidURL(let url):
            return "Invalid profile URL: \(url)"
        case .missingCredentials(let profile):
            let envPrefix = Profile.envVarPrefix(for: profile)
            return "Missing credentials for profile '\(profile)'. " +
                   "Provide in URL or set \(envPrefix)_ACCESS_KEY and \(envPrefix)_SECRET_KEY"
        }
    }
}

struct Profile: Sendable, Equatable {
    let name: String
    let endpoint: URL
    let region: String
    let bucket: String?
    let accessKeyId: String?
    let secretAccessKey: String?

    static func parse(name: String, url urlString: String) throws -> Profile {
        guard let url = URL(string: urlString), let scheme = url.scheme, url.host != nil else {
            throw ProfileError.invalidURL(urlString)
        }

        // Validate that we have a proper scheme (http or https)
        guard scheme == "http" || scheme == "https" else {
            throw ProfileError.invalidURL(urlString)
        }

        // Extract credentials from userinfo
        let accessKeyId = url.user
        let secretAccessKey = url.password

        // Parse host for bucket and region
        let host = url.host ?? ""
        let (bucket, region) = parseHost(host)

        // Rebuild endpoint URL without credentials
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ProfileError.invalidURL(urlString)
        }
        components.user = nil
        components.password = nil
        guard let endpoint = components.url else {
            throw ProfileError.invalidURL(urlString)
        }

        return Profile(
            name: name,
            endpoint: endpoint,
            region: region,
            bucket: bucket,
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey
        )
    }

    private static func parseHost(_ host: String) -> (bucket: String?, region: String) {
        // Look for .s3. marker in host
        guard let s3Range = host.range(of: ".s3.") else {
            // No .s3. marker - check if host starts with "s3."
            if host.hasPrefix("s3.") {
                let afterS3 = host.dropFirst(3) // drop "s3."
                let region = extractRegion(from: String(afterS3))
                return (nil, region)
            }
            return (nil, "auto")
        }

        // Part before .s3. is the bucket
        let bucket = String(host[..<s3Range.lowerBound])

        // Part after .s3. contains region
        let afterS3 = String(host[s3Range.upperBound...])
        let region = extractRegion(from: afterS3)

        return (bucket.isEmpty ? nil : bucket, region)
    }

    private static func extractRegion(from hostPart: String) -> String {
        // Region is everything up to the next dot (TLD or domain)
        guard let dotIndex = hostPart.firstIndex(of: ".") else {
            return hostPart.isEmpty ? "auto" : hostPart
        }
        let region = String(hostPart[..<dotIndex])

        // Check if this looks like a TLD/domain instead of a region
        // Common TLDs, domain names, and reserved words that indicate no region was specified
        let nonRegionDomains = [
            "com", "org", "net", "io", "co",
            "example", "localhost", "amazonaws", "backblazeb2"
        ]
        if nonRegionDomains.contains(region) {
            return "auto"
        }

        return region.isEmpty ? "auto" : region
    }

    static func envVarPrefix(for profileName: String) -> String {
        let normalized = profileName
            .uppercased()
            .map { $0.isLetter || $0.isNumber ? $0 : Character("_") }
        return "SS3_\(String(normalized))"
    }
}

struct ResolvedProfile: Sendable {
    let name: String
    let endpoint: URL
    let region: String
    let bucket: String?
    let accessKeyId: String
    let secretAccessKey: String
    let pathStyle: Bool
}

extension Profile {
    func resolve(with env: Environment, pathStyle: Bool = false) throws -> ResolvedProfile {
        let envPrefix = Profile.envVarPrefix(for: name)

        // Environment variables take precedence over URL credentials
        let resolvedAccessKey = env.value(for: "\(envPrefix)_ACCESS_KEY") ?? accessKeyId
        let resolvedSecretKey = env.value(for: "\(envPrefix)_SECRET_KEY") ?? secretAccessKey

        guard let accessKey = resolvedAccessKey, let secretKey = resolvedSecretKey else {
            throw ProfileError.missingCredentials(profile: name)
        }

        return ResolvedProfile(
            name: name,
            endpoint: endpoint,
            region: region,
            bucket: bucket,
            accessKeyId: accessKey,
            secretAccessKey: secretKey,
            pathStyle: pathStyle
        )
    }
}
