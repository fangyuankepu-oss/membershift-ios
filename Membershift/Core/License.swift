import Foundation

/// Trial / activation status, aligned with the Android native app:
/// 3-month (90-day) trial from `license.installed_at` (first-install date).
enum LicenseStatus: Equatable {
    /// Trial running, with days left (0 = last day).
    case trial(daysLeft: Int)
    /// Activated with a code; `expires` is "YYYY-MM-DD" or nil for perpetual.
    case activated(expires: String?)
    /// Trial expired and no valid code on file.
    case expired
}

/// Placeholder verifier interface.
///
/// The real MP- activation-code scheme is deliberately NOT implemented
/// here, and NO signing key is stored in the client — the Android
/// generator secret stays seller-only (same rule as the Android project:
/// the key must never appear in client code, docs, or reports).
///
/// Phase 2 must decide, with the user: reuse the offline MP- scheme
/// (same accepted reverser risk as Android) or move to server-side
/// verification. Until then `verify` always fails and `status` only
/// reports the trial window; a stored code is reported as activated
/// (placeholder behaviour, kept for UI wiring only).
protocol LicenseVerifying {
    func status(db: Database) -> LicenseStatus
    func verify(code: String) -> Bool
}

struct StubLicenseVerifier: LicenseVerifying {
    static let trialDays = 90

    func status(db: Database) -> LicenseStatus {
        let code = db.licenseValue("code", default: "")
        if !code.isEmpty {
            let expires = db.licenseValue("expires_at", default: "")
            return .activated(expires: expires.isEmpty ? nil : expires)
        }
        let installed = db.licenseValue("installed_at", default: "")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let installedDate = formatter.date(from: installed) else {
            return .trial(daysLeft: Self.trialDays)
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: installedDate)
        let today = calendar.startOfDay(for: Date())
        let elapsed = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        let left = Self.trialDays - elapsed
        return left >= 0 ? .trial(daysLeft: left) : .expired
    }

    func verify(code: String) -> Bool {
        // Placeholder: no real verification in the skeleton.
        false
    }
}
