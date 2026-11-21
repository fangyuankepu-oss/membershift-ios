import SwiftUI

/// Dashboard (manager view) — phase 2, first real page. Mirrors Android
/// `DashboardPage` / WebView `renderDashboard` (manager):
///
/// - 6 stat cards: 会员总数 / 今日营业额 / 本月营业额 / 累计发放积分 /
///   累计消耗积分 / 储值总余额.
/// - 积分将过期提醒卡 (30 days, from points_ledger).
/// - 近 14 天营业额 bar chart (self-drawn, no chart library).
/// - 消费 TOP 5 (with tier badge) + 未来 7 天生日.
/// - 最近流水 (latest 8 transactions) + 刷新 button.
///
/// The staff view (own-today-only) is NOT implemented here — the iOS
/// app has no permission system yet (phase-2 item, same as the
/// skeleton); the logged-in user is the manager admin account.
///
/// All values come from the SQLite DB via `Database`. On first
/// appearance, when the members and transactions tables are both empty,
/// the ported Android demo data is auto-loaded (no tap needed) so a
/// fresh install shows real numbers immediately.
struct DashboardView: View {
    @State private var data = DashboardData.empty
    @State private var didAutoLoadDemo = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Button(L10n.string("dash_refresh")) { reload() }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.deepGreen)
                    .frame(maxWidth: .infinity)

                statGrid
                expiringCard
                chartCard
                topCard
                birthdayCard
                recentCard
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear { appear() }
    }

    private func appear() {
        if !didAutoLoadDemo {
            didAutoLoadDemo = true
            let db = Database.shared
            let members = db.scalarInt("SELECT COUNT(*) FROM members") ?? 0
            let transactions = db.scalarInt("SELECT COUNT(*) FROM transactions") ?? 0
            if members == 0 && transactions == 0 {
                _ = DemoData.loadIfNeeded(db: db)
            }
        }
        reload()
    }

    private func reload() {
        data = DashboardData.load(db: Database.shared)
    }

    // MARK: - Stat cards (2 columns, same order as Android)

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            statCard(labelKey: "dash_members", value: "\(data.memberCount)")
            statCard(labelKey: "dash_today_sales", value: data.money(data.todaySales))
            statCard(labelKey: "dash_month_sales", value: data.money(data.monthSales))
            statCard(labelKey: "dash_points_issued", value: "\(data.pointsIssued)")
            statCard(labelKey: "dash_points_used", value: "\(data.pointsUsed)")
            statCard(labelKey: "dash_balance_total", value: data.money(data.balanceTotal))
        }
    }

    private func statCard(labelKey: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.string(labelKey))
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3)
                .bold()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    // MARK: - Sections

    private func sectionCard<Content: View>(titleKey: String,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string(titleKey))
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    private var expiringCard: some View {
        sectionCard(titleKey: "dash_expiring_title") {
            if data.expiringMemberCount > 0 {
                let key = data.expiringMemberCount == 1 ? "dash_expiring_one" : "dash_expiring_fmt"
                Text(String(format: L10n.string(key),
                            Int(data.expiringMemberCount),
                            Int(data.expiringPoints),
                            data.expiringNearest))
            } else {
                Text(L10n.string("dash_expiring_none"))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var chartCard: some View {
        sectionCard(titleKey: "dash_chart_title") {
            if data.dailySalesTotal > 0 {
                barChart
            } else {
                Text(L10n.string("dash_chart_empty"))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var barChart: some View {
        let maxValue = max(data.dailySales.map { $0.amount }.max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(data.dailySales.indices, id: \.self) { index in
                let day = data.dailySales[index]
                VStack(spacing: 2) {
                    Text(day.amount > 0 ? "\(Int(day.amount.rounded()))" : "")
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundColor(.secondary)
                    Rectangle()
                        .fill(Brand.deepGreen)
                        .frame(width: 14, height: max(3, day.amount / maxValue * 90))
                    Text(day.label)
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 160)
    }

    private var topCard: some View {
        sectionCard(titleKey: "dash_top_title") {
            if data.topMembers.isEmpty {
                Text(L10n.string("dash_top_empty"))
                    .foregroundColor(.secondary)
            } else {
                ForEach(data.topMembers.indices, id: \.self) { index in
                    let member = data.topMembers[index]
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(width: 20, alignment: .leading)
                        Text(member.name)
                            .lineLimit(1)
                        if !member.tierName.isEmpty {
                            Text(member.tierName)
                                .font(.caption)
                                .bold()
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(hex: member.tierColor))
                                .cornerRadius(8)
                        }
                        Spacer()
                        Text(data.moneyTrim(member.spent))
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var birthdayCard: some View {
        sectionCard(titleKey: "dash_birthday_title") {
            if data.birthdays.isEmpty {
                Text(L10n.string("dash_birthday_none"))
                    .foregroundColor(.secondary)
            } else {
                ForEach(data.birthdays.indices, id: \.self) { index in
                    let birthday = data.birthdays[index]
                    HStack(spacing: 8) {
                        Text("🎂")
                        Text(birthday.name)
                            .lineLimit(1)
                        Spacer()
                        Text(birthday.md)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var recentCard: some View {
        sectionCard(titleKey: "dash_recent_title") {
            if data.recentTx.isEmpty {
                Text(L10n.string("dash_recent_empty"))
                    .foregroundColor(.secondary)
            } else {
                ForEach(data.recentTx.indices, id: \.self) { index in
                    let tx = data.recentTx[index]
                    HStack(spacing: 8) {
                        Text(tx.timeLabel)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("\(tx.typeName) · \(tx.memberName)")
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer()
                        Text(tx.rightText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .layoutPriority(1)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

// MARK: - Data

struct DashboardTopMember {
    let name: String
    let tierName: String
    let tierColor: String
    let spent: Double
}

struct DashboardBirthday {
    let name: String
    let md: String
    let daysLeft: Int
}

struct DashboardRecentTx {
    let timeLabel: String
    let typeName: String
    let memberName: String
    /// Amount + points, e.g. "$268.00 +268 分" (Android `makeRow` right side).
    let rightText: String
}

/// All Dashboard values, read from the DB in one pass. Query shapes
/// mirror Android `Store` (same SQL, same date rules).
struct DashboardData {
    let currency: String
    let memberCount: Int64
    let todaySales: Double
    let monthSales: Double
    let pointsIssued: Int64
    let pointsUsed: Int64
    let balanceTotal: Double
    let expiringMemberCount: Int64
    let expiringPoints: Int64
    let expiringNearest: String
    let dailySales: [(label: String, amount: Double)]
    let dailySalesTotal: Double
    let topMembers: [DashboardTopMember]
    let birthdays: [DashboardBirthday]
    let recentTx: [DashboardRecentTx]

    static let empty = DashboardData(
        currency: "$", memberCount: 0, todaySales: 0, monthSales: 0,
        pointsIssued: 0, pointsUsed: 0, balanceTotal: 0,
        expiringMemberCount: 0, expiringPoints: 0, expiringNearest: "",
        dailySales: [], dailySalesTotal: 0,
        topMembers: [], birthdays: [], recentTx: [])

    /// Currency + 2 decimals, like Android `Store.money`.
    static func money(_ amount: Double, currency: String) -> String {
        String(format: "%@%.2f", currency, amount)
    }

    /// Drops the decimals for whole amounts, like Android
    /// `Store.moneyTrim`.
    static func moneyTrim(_ amount: Double, currency: String) -> String {
        if amount == floor(amount) {
            return String(format: "%@%.0f", currency, amount)
        }
        return money(amount, currency: currency)
    }

    func money(_ amount: Double) -> String {
        Self.money(amount, currency: currency)
    }

    func moneyTrim(_ amount: Double) -> String {
        Self.moneyTrim(amount, currency: currency)
    }

    static func load(db: Database) -> DashboardData {
        let today = AppDates.today()
        let monthStart = AppDates.monthStart()
        let currency = db.settingValue("currency", default: "$")

        func sumTx(_ start: String, _ end: String) -> Double {
            let rows = db.query(
                "SELECT COALESCE(SUM(amount),0) AS v FROM transactions WHERE type IN ('checkout','earn') AND date(created_at) >= ? AND date(created_at) <= ?",
                bindings: [.text(start), .text(end)])
            return rows.first?.real("v") ?? 0
        }

        let memberCount = db.scalarInt("SELECT COUNT(*) FROM members") ?? 0
        let todaySales = sumTx(today, today)
        let monthSales = sumTx(monthStart, today)
        let pointsIssued = db.scalarInt(
            "SELECT COALESCE(SUM(points_change),0) FROM transactions WHERE points_change > 0") ?? 0
        let pointsUsedNegative = db.scalarInt(
            "SELECT COALESCE(SUM(points_change),0) FROM transactions WHERE points_change < 0") ?? 0
        let balanceTotal = db.scalarReal(
            "SELECT COALESCE(SUM(balance),0) FROM members") ?? 0

        // Points expiring within 30 days (ledger is the truth).
        let limit = AppDates.addDays(today, 30)
        let expiringRows = db.query(
            "SELECT COUNT(DISTINCT member_id) AS c, COALESCE(SUM(points_total - points_used),0) AS p, MIN(expiry_date) AS d FROM points_ledger WHERE expiry_date <> '' AND expiry_date >= ? AND expiry_date <= ? AND (points_total - points_used) > 0",
            bindings: [.text(today), .text(limit)])
        let expiringMemberCount = expiringRows.first?.int("c") ?? 0
        let expiringPoints = expiringRows.first?.int("p") ?? 0
        let expiringNearest = expiringRows.first?.text("d") ?? ""

        // Last 14 days of sales, oldest first.
        var dailySales: [(label: String, amount: Double)] = []
        var dailySalesTotal: Double = 0
        for offset in (0...13).reversed() {
            let day = AppDates.addDays(today, -offset)
            let amount = sumTx(day, day)
            dailySales.append((label: String(day.suffix(2)), amount: amount))
            dailySalesTotal += amount
        }

        // Tiers (for the TOP 5 badge): highest tier whose threshold the
        // member's total spent reaches, else the first tier.
        let tiers = db.query("SELECT name, min_spent, color FROM tiers ORDER BY min_spent ASC")
            .map { (name: $0.text("name"), minSpent: $0.real("min_spent"), color: $0.text("color")) }
        func tierFor(_ spent: Double) -> (name: String, color: String) {
            var best: (name: String, color: String)? = nil
            for tier in tiers where tier.minSpent <= spent {
                best = (tier.name, tier.color)
            }
            if let best { return best }
            if let first = tiers.first { return (first.name, first.color) }
            return ("", "")
        }
        let topMembers = db.query(
            "SELECT name, total_spent FROM members WHERE total_spent > 0 ORDER BY total_spent DESC LIMIT 5")
            .map { row -> DashboardTopMember in
                let spent = row.real("total_spent")
                let tier = tierFor(spent)
                return DashboardTopMember(name: row.text("name"), tierName: tier.name,
                                          tierColor: tier.color, spent: spent)
            }

        // Birthdays in the next 7 days, soonest first.
        let birthdays = db.query("SELECT name, birthday FROM members")
            .compactMap { row -> DashboardBirthday? in
                let birthday = row.text("birthday")
                guard let daysLeft = AppDates.daysUntilBirthday(birthday),
                      daysLeft <= 7 else { return nil }
                return DashboardBirthday(name: row.text("name"),
                                         md: AppDates.birthdayMd(birthday),
                                         daysLeft: daysLeft)
            }
            .sorted { $0.daysLeft < $1.daysLeft }

        // Latest 8 transactions.
        var memberNames: [Int64: String] = [:]
        for row in db.query("SELECT id, name FROM members") {
            memberNames[row.int("id")] = row.text("name")
        }
        let recentTx = db.query(
            "SELECT type, member_id, amount, points_change, created_at FROM transactions ORDER BY id DESC LIMIT 8")
            .map { row -> DashboardRecentTx in
                let memberId = row.int("member_id")
                let memberName = memberId > 0
                    ? (memberNames[memberId] ?? L10n.string("dash_tx_guest"))
                    : L10n.string("dash_tx_guest")
                let createdAt = row.text("created_at")
                // Date only ("11-18"): the time made the row too wide
                // and squeezed the name and the amount into "...".
                let timeLabel = createdAt.count >= 10
                    ? String(createdAt.prefix(10).dropFirst(5))
                    : createdAt
                let amount = row.real("amount")
                let pointsChange = row.int("points_change")
                var rightText = moneyTrim(amount, currency: currency)
                if pointsChange != 0 {
                    let sign = pointsChange > 0 ? "+" : ""
                    rightText += " " + sign + String(format: L10n.string("mem_points_fmt"),
                                                      Int(pointsChange))
                }
                return DashboardRecentTx(timeLabel: timeLabel,
                                         typeName: txTypeName(row.text("type")),
                                         memberName: memberName,
                                         rightText: rightText)
            }

        return DashboardData(
            currency: currency, memberCount: memberCount,
            todaySales: todaySales, monthSales: monthSales,
            pointsIssued: pointsIssued, pointsUsed: -pointsUsedNegative,
            balanceTotal: balanceTotal,
            expiringMemberCount: expiringMemberCount,
            expiringPoints: expiringPoints, expiringNearest: expiringNearest,
            dailySales: dailySales, dailySalesTotal: dailySalesTotal,
            topMembers: topMembers, birthdays: birthdays, recentTx: recentTx)
    }
}

/// Transaction type name, mirroring Android `DashboardPage.txTypeName`.
private func txTypeName(_ type: String) -> String {
    switch type {
    case "checkout": return L10n.string("tx_checkout")
    case "earn": return L10n.string("tx_earn")
    case "recharge": return L10n.string("tx_recharge")
    case "exchange": return L10n.string("tx_exchange")
    case "adjust": return L10n.string("tx_adjust")
    case "points_expire": return L10n.string("tx_points_expire")
    case "referral": return L10n.string("tx_referral")
    case "coupon_redeem": return L10n.string("tx_coupon_redeem")
    default: return L10n.string("tx_unknown")
    }
}

private extension Color {
    /// "#145a47" style hex (tiers store colours this way in the DB).
    init(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        var rgb: UInt64 = 0
        _ = Scanner(string: cleaned).scanHexInt64(&rgb)
        self.init(red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }
}
