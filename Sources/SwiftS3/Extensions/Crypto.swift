import Foundation

// TODO: Consider using a cross-platform crypto library (e.g., swift-crypto) for better
// performance and security auditing. See: https://github.com/dave-atx/swift-s3/issues/2
extension Data {
    func sha256() -> Data {
        SHA256.hash(data: self)
    }

    func hmacSHA256(key: Data) -> Data {
        HMAC.authenticationCode(for: self, using: key)
    }
}

// Pure Swift SHA256 implementation for cross-platform compatibility (macOS + Linux).
// TODO: Consider replacing with swift-crypto for production use. See issue #2.
enum SHA256 {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    static func hash(data: Data) -> Data {
        var h0: UInt32 = 0x6a09e667
        var h1: UInt32 = 0xbb67ae85
        var h2: UInt32 = 0x3c6ef372
        var h3: UInt32 = 0xa54ff53a
        var h4: UInt32 = 0x510e527f
        var h5: UInt32 = 0x9b05688c
        var h6: UInt32 = 0x1f83d9ab
        var h7: UInt32 = 0x5be0cd19

        let paddedData = pad(data)
        let chunks = paddedData.count / 64

        for i in 0..<chunks {
            let chunk = paddedData.subdata(in: i * 64..<(i + 1) * 64)
            var w = [UInt32](repeating: 0, count: 64)

            for j in 0..<16 {
                w[j] = UInt32(chunk[j * 4]) << 24 |
                       UInt32(chunk[j * 4 + 1]) << 16 |
                       UInt32(chunk[j * 4 + 2]) << 8 |
                       UInt32(chunk[j * 4 + 3])
            }

            for j in 16..<64 {
                let s0 = rightRotate(w[j - 15], by: 7) ^ rightRotate(w[j - 15], by: 18) ^ (w[j - 15] >> 3)
                let s1 = rightRotate(w[j - 2], by: 17) ^ rightRotate(w[j - 2], by: 19) ^ (w[j - 2] >> 10)
                w[j] = w[j - 16] &+ s0 &+ w[j - 7] &+ s1
            }

            var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7

            for j in 0..<64 {
                let S1 = rightRotate(e, by: 6) ^ rightRotate(e, by: 11) ^ rightRotate(e, by: 25)
                let ch = (e & f) ^ (~e & g)
                let temp1 = h &+ S1 &+ ch &+ k[j] &+ w[j]
                let S0 = rightRotate(a, by: 2) ^ rightRotate(a, by: 13) ^ rightRotate(a, by: 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = S0 &+ maj

                h = g
                g = f
                f = e
                e = d &+ temp1
                d = c
                c = b
                b = a
                a = temp1 &+ temp2
            }

            h0 = h0 &+ a
            h1 = h1 &+ b
            h2 = h2 &+ c
            h3 = h3 &+ d
            h4 = h4 &+ e
            h5 = h5 &+ f
            h6 = h6 &+ g
            h7 = h7 &+ h
        }

        var result = Data()
        for value in [h0, h1, h2, h3, h4, h5, h6, h7] {
            result.append(UInt8((value >> 24) & 0xFF))
            result.append(UInt8((value >> 16) & 0xFF))
            result.append(UInt8((value >> 8) & 0xFF))
            result.append(UInt8(value & 0xFF))
        }
        return result
    }

    private static func pad(_ data: Data) -> Data {
        var padded = data
        let originalLength = UInt64(data.count * 8)

        padded.append(0x80)

        while (padded.count % 64) != 56 {
            padded.append(0x00)
        }

        for i in (0..<8).reversed() {
            padded.append(UInt8((originalLength >> (i * 8)) & 0xFF))
        }

        return padded
    }

    private static func rightRotate(_ value: UInt32, by amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }
}

// HMAC-SHA256 implementation for cross-platform compatibility.
// TODO: Consider replacing with swift-crypto for production use. See issue #2.
enum HMAC {
    static func authenticationCode(for message: Data, using key: Data) -> Data {
        let blockSize = 64
        var keyBytes = key

        if keyBytes.count > blockSize {
            keyBytes = SHA256.hash(data: keyBytes)
        }

        if keyBytes.count < blockSize {
            keyBytes.append(Data(repeating: 0, count: blockSize - keyBytes.count))
        }

        var outerKeyPad = Data(repeating: 0x5c, count: blockSize)
        var innerKeyPad = Data(repeating: 0x36, count: blockSize)

        for i in 0..<blockSize {
            outerKeyPad[i] ^= keyBytes[i]
            innerKeyPad[i] ^= keyBytes[i]
        }

        let innerHash = SHA256.hash(data: innerKeyPad + message)
        return SHA256.hash(data: outerKeyPad + innerHash)
    }
}
