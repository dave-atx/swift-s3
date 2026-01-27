import Foundation

enum ProfileResolverError: Error, CustomStringConvertible {
    case unknownProfile(name: String, available: [String])
    case noConfig(profileName: String)

    var description: String {
        switch self {
        case .unknownProfile(let name, let available):
            if available.isEmpty {
                return "Unknown profile '\(name)'. No config file found.\n" +
                       "Use --profile <name> <url> to specify endpoint."
            }
            return "Unknown profile '\(name)'. Available profiles: \(available.joined(separator: ", "))\n" +
                   "Use --profile <name> <url> to specify endpoint."
        case .noConfig(let profileName):
            return "Unknown profile '\(profileName)'. No config file found.\n" +
                   "Use --profile <name> <url> to specify endpoint."
        }
    }
}

struct ProfileResolver: Sendable {
    let config: ConfigFile?

    func resolve(
        profileName: String,
        cliOverride: (name: String, url: String)?
    ) throws -> Profile {
        // CLI override takes precedence
        if let override = cliOverride, override.name == profileName {
            return try Profile.parse(name: override.name, url: override.url)
        }

        // Look up in config
        guard let config = config else {
            throw ProfileResolverError.noConfig(profileName: profileName)
        }

        guard let url = config.profileURL(for: profileName) else {
            throw ProfileResolverError.unknownProfile(
                name: profileName,
                available: config.availableProfiles
            )
        }

        return try Profile.parse(name: profileName, url: url)
    }
}
