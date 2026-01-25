import ArgumentParser

struct GlobalOptions: ParsableArguments {
    @Option(name: [.long, .customShort("u")], help: "Access key ID")
    var keyId: String?

    @Option(name: [.long, .customShort("p")], help: "Secret access key")
    var secretKey: String?

    @Option(help: "AWS region")
    var region: String?

    @Option(help: "S3 endpoint URL")
    var endpoint: String?

    @Option(help: "Bucket name")
    var bucket: String?

    @Flag(name: .long, help: "Use Backblaze B2 endpoint")
    var b2: Bool = false

    @Flag(help: "Verbose error output")
    var verbose: Bool = false

    @Option(help: "Output format (human, json, tsv)")
    var format: OutputFormat = .human
}

struct ResolvedConfiguration: Sendable {
    let keyId: String?
    let secretKey: String?
    let region: String?
    let endpoint: String?
    let bucket: String?
    let verbose: Bool
    let format: OutputFormat
}

extension GlobalOptions {
    func resolve(with env: Environment) -> ResolvedConfiguration {
        let resolvedRegion = region ?? env.value(for: "SS3_REGION")

        var resolvedEndpoint = endpoint ?? env.value(for: "SS3_ENDPOINT")
        if b2, let region = resolvedRegion {
            resolvedEndpoint = "https://s3.\(region).backblazeb2.com"
        }

        return ResolvedConfiguration(
            keyId: keyId ?? env.value(for: "SS3_ACCESS_KEY"),
            secretKey: secretKey ?? env.value(for: "SS3_SECRET_KEY"),
            region: resolvedRegion,
            endpoint: resolvedEndpoint,
            bucket: bucket ?? env.value(for: "SS3_BUCKET"),
            verbose: verbose,
            format: format
        )
    }
}
