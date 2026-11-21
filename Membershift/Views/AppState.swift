import Foundation

/// Session + language state. Android persists the session in localStorage
/// (`ms_session`); the skeleton keeps it in memory only — persisting the
/// session across launches is a phase-2 item.
final class AppState: ObservableObject {
    @Published var currentUser: Auth.User?

    @Published var language: AppLanguage {
        didSet { L10n.current = language }
    }

    init() {
        language = L10n.current
    }

    var isLoggedIn: Bool { currentUser != nil }

    func logout() {
        currentUser = nil
    }
}
