import SwiftUI

/// Main navigation shell — the same 9 tabs as the Android native app
/// (`HomeActivity.NAV`, in-nav items only), in the same order:
/// Dashboard, Statistics, Members, Booking, Recharge & Deduct, Gifts,
/// Coupons, Transactions, Settings.
///
/// Android notes carried over:
/// - Checkout is OFF the nav in Android too (`inNav=false`); it is not
///   a tab here either (restore by adding a tab later).
/// - "Earn points" (消费兑换积分) is a section inside the Recharge page
///   on Android, not its own tab — same here.
/// - Permission-based hiding (14 permission keys, manager sees all) is
///   a phase-2 item; the skeleton shows all 9 tabs.
struct MainTabView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            tabPage(titleKey: "nav_dashboard", icon: "square.grid.2x2", page: "dashboard")
            tabPage(titleKey: "nav_stats", icon: "chart.bar.fill", page: "statistics")
            tabPage(titleKey: "nav_members", icon: "person.2.fill", page: "members")
            tabPage(titleKey: "nav_booking", icon: "calendar", page: "booking")
            tabPage(titleKey: "nav_recharge", icon: "arrow.left.arrow.right", page: "recharge")
            tabPage(titleKey: "nav_gifts", icon: "gift.fill", page: "gifts")
            tabPage(titleKey: "nav_coupons", icon: "ticket.fill", page: "coupons")
            tabPage(titleKey: "nav_transactions", icon: "list.bullet.rectangle", page: "transactions")
            tabPage(titleKey: "nav_settings", icon: "gearshape.fill", page: "settings")
        }
        .tint(Brand.deepGreen)
    }

    private func tabPage(titleKey: String, icon: String, page: String) -> some View {
        NavigationStack {
            PlaceholderPage(titleKey: titleKey, page: page)
                .navigationTitle(L10n.string(titleKey))
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(L10n.string("logout")) { appState.logout() }
                    }
                }
        }
        .tabItem { Label(L10n.string(titleKey), systemImage: icon) }
    }
}
