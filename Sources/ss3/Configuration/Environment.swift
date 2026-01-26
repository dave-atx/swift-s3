import Foundation

struct Environment: Sendable {
    private let getenv: @Sendable (String) -> String?

    init(getenv: @Sendable @escaping (String) -> String? = { ProcessInfo.processInfo.environment[$0] }) {
        self.getenv = getenv
    }

    func value(for key: String) -> String? {
        getenv(key)
    }
}
