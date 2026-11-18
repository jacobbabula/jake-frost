import Foundation
import CryptoKit
import Security
import CommonCrypto

/// The Windows gift format authenticates IV + AES-CBC ciphertext using a separate HMAC key.
enum MacFriendEnvelope {
    static func random(_ count: Int) throws -> Data {
        var bytes = Data(count: count)
        let rc = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        guard rc == errSecSuccess else { throw GiftProblem.message("Couldn’t create a secure invitation.") }
        return bytes
    }

    private static func urlToken(_ bytes: Data) -> String {
        bytes.base64EncodedString().replacingOccurrences(of:"+",with:"-")
            .replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
    }

    static func token() throws -> String { urlToken(try random(32)) }
    static func key(_ token: String) throws -> SymmetricKey {
        guard token.utf8.count == 43,
              let data = Data(base64Encoded:token.replacingOccurrences(of:"-",with:"+")
                                .replacingOccurrences(of:"_",with:"/") + "="),
              data.count == 32, urlToken(data) == token else {
            throw GiftProblem.message("Paste the complete JF1 invitation code.")
        }
        return SymmetricKey(data:data)
    }

    private static func derived(_ token: String, _ label: String) throws -> Data {
        Data(HMAC<SHA256>.authenticationCode(for:Data(("JakeFrostPost/1/" + label).utf8),using:try key(token)))
    }

    static func id(_ token: String) throws -> String {
        try derived(token,"address").prefix(16).map { String(format:"%02x",$0) }.joined()
    }
    static func proof(_ token: String) throws -> String { urlToken(try derived(token,"claim")) }

    private static func crypt(_ operation: CCOperation, _ input: Data, _ key: Data, _ iv: Data) throws -> Data {
        let capacity = input.count + kCCBlockSizeAES128
        var output = Data(count:capacity), written = 0
        let rc = output.withUnsafeMutableBytes { dst in key.withUnsafeBytes { k in iv.withUnsafeBytes { vector in
            input.withUnsafeBytes { src in
                CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                        k.baseAddress, key.count, vector.baseAddress, src.baseAddress, input.count,
                        dst.baseAddress, capacity, &written)
            }
        } } }
        guard rc == kCCSuccess else { throw GiftProblem.message("Invalid encrypted gift.") }
        return output.prefix(written)
    }

    static func seal(_ text: String, secret: String, label: String) throws -> String {
        let iv = try random(kCCBlockSizeAES128)
        let body = try iv + crypt(CCOperation(kCCEncrypt),Data(text.utf8),derived(secret,"encrypt/"+label),iv)
        let authentication = HMAC<SHA256>.authenticationCode(for:body,using:SymmetricKey(data:try derived(secret,"authenticate/"+label)))
        return (body + Data(authentication)).base64EncodedString()
    }

    static func open(_ envelope: String, secret: String, label: String) throws -> String {
        guard envelope.utf8.count <= 28_000, let bytes = Data(base64Encoded:envelope),
              bytes.count >= 64, bytes.count % 16 == 0 else { throw GiftProblem.message("Invalid encrypted gift.") }
        let body = bytes.dropLast(32)
        guard HMAC<SHA256>.isValidAuthenticationCode(bytes.suffix(32),authenticating:body,
                using:SymmetricKey(data:try derived(secret,"authenticate/"+label))) else {
            throw GiftProblem.message("The encrypted gift could not be authenticated.")
        }
        let clear = try crypt(CCOperation(kCCDecrypt),Data(body.dropFirst(16)),derived(secret,"encrypt/"+label),Data(body.prefix(16)))
        guard let text = String(data:clear,encoding:.utf8) else { throw GiftProblem.message("Invalid encrypted gift.") }
        return text
    }
}

