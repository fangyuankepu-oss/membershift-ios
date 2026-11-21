import SwiftUI

/// Membershift iOS — phase 1 skeleton.
///
/// Opens the SQLite database on launch (creating + seeding it on first
/// run), then shows the login screen; after login, the 9-tab navigation
/// shell. All pages are placeholders in this phase.
@main
struct MembershiftApp: App {
    @StateObject private var appState = AppState()
    @State private var dbError: String?

    init() {
        if !Database.shared.open() {
            _dbError = State(initialValue: Database.shared.openError
                ?? "Unknown database error")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let dbError {
                    DatabaseErrorView(message: dbError)
                } else if appState.currentUser == nil {
                    LoginView()
                } else {
                    MainTabView()
                }
            }
            .environmentObject(appState)
        }
    }
}
