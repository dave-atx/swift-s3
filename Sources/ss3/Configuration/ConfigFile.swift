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

    func profileURL(for name: String) -> String? {
        profiles[name]
    }

    var availableProfiles: [String] {
        profiles.keys.sorted()
    }
}
