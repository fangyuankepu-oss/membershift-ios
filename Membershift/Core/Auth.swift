import CryptoKit
import Foundation

/// Password hashing and login verification, aligned with Android
/// `AuthHelper` and the original WebView `loginUser` / `hashPw`:
///
///     pw_hash = sha256(salt + "::" + password)   (UTF-8)
///
/// Legacy compatibility: the old JS implementation hashed the same string
/// as Latin-1 bytes. For ASCII passwords the two digests are identical;
/// for a stored hash that only matches the Latin-1 digest, login still
/// succeeds and the stored hash is upgraded to the standard UTF-8 digest.
enum Auth {
    struct User: Identifiable {
        let id: Int64
        let username: String
        let role: String
        let permsJSON: String
        var isManager: Bool { role == "manager" }
    }

    static func sha256Hex(_ input: String, latin1: Bool = false) -> String {
        let data: Data?
        if latin1 {
            data = input.data(using: .isoLatin1)
        } else {
            data = input.data(using: .utf8)
        }
        guard let data else { return "" }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// hashPw(pw, salt) = sha256(salt + "::" + pw)
    static func hashPassword(_ password: String, salt: String) -> String {
        sha256Hex(salt + "::" + password)
    }

    /// Same as Android `makeSalt`: random base36 + timestamp base36.
    static func makeSalt() -> String {
        let random = UInt64.random(in: 0..<2_176_782_336)
        let millis = Int64(Date().timeIntervalSince1970 * 1000)
        return String(random, radix: 36) + String(millis, radix: 36)
    }

    /// Verifies username / password. Returns the user on success, nil on
    /// failure. A legacy Latin-1 hash hit upgrades the stored hash.
    static func verify(username: String, password: String, db: Database) -> User? {
        guard let row = db.queryUser(username: username), !row.hash.isEmpty else {
            return nil
        }
        let current = hashPassword(password, salt: row.salt)
        var legacyHit = false
        if current != row.hash {
            let legacy = sha256Hex(row.salt + "::" + password, latin1: true)
            guard legacy == row.hash else { return nil }
            legacyHit = true
        }
        if legacyHit {
            _ = db.updateUserHash(userId: row.id, hash: current)
        }
        return User(id: row.id, username: row.username, role: row.role, permsJSON: row.perms)
    }
}
