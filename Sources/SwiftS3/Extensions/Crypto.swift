import Crypto
import Foundation

extension Data {
    func sha256() -> Data {
        Data(Crypto.SHA256.hash(data: self))
    }

    func hmacSHA256(key: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let mac = Crypto.HMAC<SHA256>.authenticationCode(for: self, using: symmetricKey)
        return Data(mac)
    }
}
