import Foundation

enum ConfigFileError: Error, CustomStringConvertible {
    case malformedJSON(path: String, underlying: Error)
    case unreadable(path: String, underlying: Error)

    var description: String {
        switch self {
        case .malformedJSON(let path, let underlying):
            return "Malformed config file at \(path): \(underlying.localizedDescription)"
        case .unreadable(let path, let underlying):
            return "Cannot read config file at \(path): \(underlying.localizedDescription)"
        }
    }
}

struct ConfigFile: Sendable {
    private let profiles: [String: String]

    init(profiles: [String: String]) {
        self.profiles = profiles
    }

    static func load(from path: String) throws -> ConfigFile? {
        let url = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ConfigFileError.unreadable(path: path, underlying: error)
        }

        do {
            let profiles = try JSONDecoder().decode([String: String].self, from: data)
            return ConfigFile(profiles: profiles)
        } catch {
            throw ConfigFileError.malformedJSON(path: path, underlying: error)
        }
    }

    static func defaultPath(env: Environment = Environment()) -> String? {
        if let xdgConfig = env.value(for: "XDG_CONFIG_HOME") {
            return "\(xdgConfig)/ss3/profiles.json"
        }
        if let home = env.value(for: "HOME") {
            return "\(home)/.config/ss3/profiles.json"
        }
        return nil
    }

    static func loadDefault(env: Environment = Environment()) throws -> ConfigFile? {
        guard let path = defaultPath(env: env) else {
            return nil
        }
        return try load(from: path)
    }

    func profileURL(for name: String) -> String? {
        profiles[name]
    }

    var availableProfiles: [String] {
        profiles.keys.sorted()
    }
}
