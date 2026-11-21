import SwiftUI

/// Placeholder content for a not-yet-built page. Every tab in the
/// skeleton uses this; phase 2 replaces each one with its real page
/// (same names as the Android pages: DashboardPage, StatisticsPage,
/// MembersPage, BookingPage, RechargePage, GiftsPage, CouponsPage,
/// TransactionsPage, SettingsPage).
struct PlaceholderPage: View {
    let titleKey: String
    let page: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hammer.fill")
                .font(.largeTitle)
                .foregroundColor(Brand.deepGreen)
            Text(L10n.string(titleKey))
                .font(.title2)
                .bold()
            Text(L10n.string("page_wip"))
                .foregroundColor(.secondary)
            Text(L10n.string("page_wip_detail"))
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Text("· \(page) ·")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(24)
    }
}

/// Shown when the database cannot be opened at launch.
struct DatabaseErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.red)
            Text(L10n.string("db_error"))
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }
}
