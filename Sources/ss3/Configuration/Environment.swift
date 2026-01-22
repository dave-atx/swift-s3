import Foundation

struct Environment: Sendable {
    let keyId: String?
    let secretKey: String?
    let region: String?
    let endpoint: String?
    let bucket: String?

    init(getenv: @Sendable (String) -> String? = { ProcessInfo.processInfo.environment[$0] }) {
        self.keyId = getenv("SS3_KEY_ID")
        self.secretKey = getenv("SS3_SECRET_KEY")
        self.region = getenv("SS3_REGION")
        self.endpoint = getenv("SS3_ENDPOINT")
        self.bucket = getenv("SS3_BUCKET")
    }
}
