import SwiftUI

/// Statistics — mirrors Android `StatisticsPage`.
///
/// - Range tabs: 今天 / 本周 / 本月 / 近 30 天 / 自定义 (default 近 30 天).
/// - 4 summary cards with 较上周期 comparison (same order as Android:
///   消费总额 / 充值总额 / 新增会员 / 积分兑换).
/// - 5 KPI rows: 订单数 / 活跃会员 / 复购率 / 积分兑换率 / 客单价.
/// - 消费趋势 bar chart (self-drawn, one bar per day in range).
/// - 时段分布 (6 buckets 9–11 … 19–21), 等级分析, 支付方式,
///   优惠券统计, 礼品兑换 Top 5.
/// - 每日明细 table: sortable by tapping a header (default date desc),
///   10 rows per page with prev/next.
///
/// All aggregates use the same SQL and the same date rules as Android
/// `Store` (rangeSales / rangeRecharge / rangeNewMembers / …).
struct StatisticsView: View {
    // Range modes, same constants as Android (RANGE_TODAY=0 … CUSTOM=4).
    private static let rangeLabels = [
        "stats_range_today", "stats_range_week", "stats_range_month",
        "stats_range_30", "stats_range_custom",
    ]

    @State private var rangeMode = 3 // RANGE_30, Android default
    @State private var customStart: Date
    @State private var customEnd: Date
    @State private var data = StatsData.empty
    @State private var dailySortCol = 0
    @State private var dailySortAsc = false
    @State private var dailyPage = 1

    init() {
        let today = AppDates.today()
        _customStart = State(initialValue: AppDates.parseDay(AppDates.addDays(today, -29)) ?? Date())
        _customEnd = State(initialValue: AppDates.parseDay(today) ?? Date())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Button(L10n.string("dash_refresh")) { reload() }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.deepGreen)
                    .frame(maxWidth: .infinity)

                rangeBar
                if rangeMode == 4 {
                    customRangeRow
                }
                summaryGrid
                kpiCard
                chartCard
                hoursCard
                tiersCard
                payCard
                couponCard
                giftsCard
                dailyCard
            }
            .padding(16)
            // Lock the page width to the screen: the daily table below
            // is wider than its card, and without this it stretches
            // the whole page past the screen edges (swallowing the
            // padding) on a 390pt screen.
            .containerRelativeFrame(.horizontal)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear { reload() }
    }

    private func currentRange() -> (String, String) {
        let today = AppDates.today()
        switch rangeMode {
        case 0: return (today, today)
        case 1: return (AppDates.weekStart(), today)
        case 2: return (AppDates.monthStart(), today)
        case 4: return (AppDates.dayString(customStart), AppDates.dayString(customEnd))
        default: return (AppDates.addDays(today, -29), today)
        }
    }

    private func reload() {
        let range = currentRange()
        data = StatsData.load(db: Database.shared, start: range.0, end: range.1)
        dailyPage = 1
    }

    // MARK: - Range tabs (5 equal buttons, fixed 48pt, Android fix9)

    private var rangeBar: some View {
        HStack(spacing: 8) {
            ForEach(Self.rangeLabels.indices, id: \.self) { index in
                Button(L10n.string(Self.rangeLabels[index])) {
                    rangeMode = index
                    reload()
                }
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(index == rangeMode ? Brand.deepGreen : Color(.systemBackground))
                .foregroundColor(index == rangeMode ? .white : Color(.label))
                .cornerRadius(10)
            }
        }
    }

    private var customRangeRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("stats_custom_from"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                DatePicker("", selection: $customStart, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .onChange(of: customStart) { newValue in
                        if newValue > customEnd { customEnd = newValue }
                        reload()
                    }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("stats_custom_to"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                DatePicker("", selection: $customEnd, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .onChange(of: customEnd) { newValue in
                        if newValue < customStart { customStart = newValue }
                        reload()
                    }
            }
            Spacer()
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    // MARK: - Summary cards + KPI

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            summaryCard(labelKey: "stats_total_sales",
                        value: data.money(data.sales), vs: data.salesVs)
            summaryCard(labelKey: "stats_total_recharge",
                        value: data.money(data.recharge), vs: data.rechargeVs)
            summaryCard(labelKey: "stats_new_members",
                        value: "\(data.newMembers)", vs: data.newMembersVs)
            summaryCard(labelKey: "stats_points_redeemed",
                        value: "\(data.redeemed)", vs: data.redeemedVs)
        }
    }

    private func summaryCard(labelKey: String, value: String, vs: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.string(labelKey))
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3)
                .bold()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(String(format: L10n.string("stats_vs_prev"), vs))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    private var kpiCard: some View {
        sectionCard {
            kpiRow(labelKey: "stats_kpi_orders", value: "\(data.orders)")
            kpiRow(labelKey: "stats_kpi_active", value: "\(data.activeMembers)")
            kpiRow(labelKey: "stats_kpi_repeat", value: data.repeatRate)
            kpiRow(labelKey: "stats_kpi_redeem_rate", value: data.redeemRate)
            kpiRow(labelKey: "stats_kpi_avg", value: data.money(data.avgOrder))
        }
    }

    private func kpiRow(labelKey: String, value: String) -> some View {
        HStack {
            Text(L10n.string(labelKey))
            Spacer()
            Text(value)
                .bold()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Sections

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    private func sectionTitle(_ key: String) -> some View {
        Text(L10n.string(key))
            .font(.headline)
    }

    private func rowPair(left: String, right: String) -> some View {
        HStack {
            Text(left)
                .lineLimit(1)
            Spacer()
            Text(right)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }

    private var chartCard: some View {
        sectionCard {
            sectionTitle("stats_trend_title")
            if data.dailyTotal > 0 {
                let maxValue = max(data.daily.map { $0.amount }.max() ?? 0, 1)
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(data.daily.indices, id: \.self) { index in
                        let day = data.daily[index]
                        let showLabel = data.daily.count <= 14 || index % 5 == 0
                        chartBar(label: day.label, amount: day.amount,
                                 maxValue: maxValue, showLabel: showLabel,
                                 width: CGFloat(max(4, 18 - data.daily.count / 4)))
                    }
                }
                .frame(height: 160)
            } else {
                Text(L10n.string("stats_empty"))
                    .foregroundColor(.secondary)
            }
        }
    }

    // One bar pulled out of the chart ForEach so the chart body stays
    // a small expression (same failure class as MembersView, build #4).
    private func chartBar(label: String, amount: Double, maxValue: Double,
                          showLabel: Bool, width: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text(amount > 0 ? "\(Int(amount.rounded()))" : "")
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundColor(.secondary)
            Rectangle()
                .fill(Brand.deepGreen)
                .frame(width: width, height: max(3, amount / maxValue * 90))
            Text(showLabel ? label : "")
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var hoursCard: some View {
        sectionCard {
            sectionTitle("stats_hours_title")
            ForEach(data.hours.indices, id: \.self) { index in
                let bucket = data.hours[index]
                let start = 9 + index * 2
                rowPair(left: String(format: L10n.string("stats_hour_fmt"), start, start + 2),
                        right: String(format: L10n.string("stats_count_fmt"),
                                      Int(bucket.count), data.money(bucket.amount)))
            }
        }
    }

    private var tiersCard: some View {
        sectionCard {
            sectionTitle("stats_tier_title")
            if data.tiers.isEmpty {
                Text(L10n.string("stats_empty"))
                    .foregroundColor(.secondary)
            } else {
                ForEach(data.tiers.indices, id: \.self) { index in
                    let tier = data.tiers[index]
                    rowPair(left: tier.name,
                            right: String(format: L10n.string("stats_tier_right_fmt"),
                                          Int(tier.count), data.moneyTrim(tier.spent)))
                }
            }
        }
    }

    private var payCard: some View {
        sectionCard {
            sectionTitle("stats_pay_title")
            if data.pays.isEmpty {
                Text(L10n.string("stats_empty"))
                    .foregroundColor(.secondary)
            } else {
                ForEach(data.pays.indices, id: \.self) { index in
                    let pay = data.pays[index]
                    rowPair(left: StatsData.payName(pay.method), right: data.money(pay.amount))
                }
            }
        }
    }

    private var couponCard: some View {
        sectionCard {
            sectionTitle("stats_coupon_title")
            Text(String(format: L10n.string("stats_coupon_issued"), Int(data.couponsIssued))
                 + " · " + String(format: L10n.string("stats_coupon_used"), Int(data.couponsUsed))
                 + " · " + String(format: L10n.string("stats_coupon_rate"), data.couponRate))
        }
    }

    private var giftsCard: some View {
        sectionCard {
            sectionTitle("stats_gift_title")
            if data.gifts.isEmpty {
                Text(L10n.string("stats_empty"))
                    .foregroundColor(.secondary)
            } else {
                ForEach(data.gifts.indices, id: \.self) { index in
                    let gift = data.gifts[index]
                    rowPair(left: gift.name,
                            right: String(format: L10n.string("stats_gift_right_fmt"), Int(gift.count)))
                }
            }
        }
    }

    // MARK: - Daily detail (sortable, 10 rows per page, Android fix2)

    private var dailyCard: some View {
        sectionCard {
            sectionTitle("stats_daily_title")
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    dailyHeader
                    ForEach(sortedDailyPage.indices, id: \.self) { index in
                        dailyRow(sortedDailyPage[index])
                    }
                }
            }
            dailyPager
        }
    }

    private var dailyPager: some View {
        HStack {
            Button(L10n.string("stats_prev")) {
                if dailyPage > 1 { dailyPage -= 1 }
            }
            .disabled(dailyPage <= 1)
            Spacer()
            Text(String(format: L10n.string("stats_page_fmt"), dailyPage, dailyTotalPages))
                .foregroundColor(.secondary)
            Spacer()
            Button(L10n.string("stats_next")) {
                if dailyPage < dailyTotalPages { dailyPage += 1 }
            }
            .disabled(dailyPage >= dailyTotalPages)
        }
        .padding(.top, 8)
    }

    private var dailyHeader: some View {
        HStack(spacing: 0) {
            dailyHeaderCell(0, key: "stats_daily_col_date", width: 56, align: .leading)
            dailyHeaderCell(1, key: "stats_daily_col_new", width: 36, align: .trailing)
            dailyHeaderCell(2, key: "stats_daily_col_sales", width: 56, align: .trailing)
            dailyHeaderCell(3, key: "stats_daily_col_recharge", width: 56, align: .trailing)
            dailyHeaderCell(4, key: "stats_daily_col_issued", width: 40, align: .trailing)
            dailyHeaderCell(5, key: "stats_daily_col_redeemed", width: 40, align: .trailing)
            dailyHeaderCell(6, key: "stats_daily_col_active", width: 36, align: .trailing)
        }
        .padding(.vertical, 6)
    }

    private func dailyHeaderCell(_ col: Int, key: String, width: CGFloat,
                                 align: Alignment) -> some View {
        Button {
            if col == dailySortCol {
                dailySortAsc.toggle()
            } else {
                dailySortCol = col
                dailySortAsc = (col != 0)
            }
        } label: {
            Text(L10n.string(key)
                 + (col == dailySortCol ? (dailySortAsc ? " ▲" : " ▼") : ""))
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .bold(col == dailySortCol)
                .foregroundColor(col == dailySortCol ? Brand.deepGreen : .secondary)
                .frame(width: width, alignment: align)
        }
        .buttonStyle(.plain)
    }

    private func dailyRow(_ row: StatsDailyRow) -> some View {
        HStack(spacing: 0) {
            Text(String(row.day.dropFirst(5)))
                .font(.caption).frame(width: 56, alignment: .leading)
            Text("\(row.newMembers)")
                .font(.caption).frame(width: 36, alignment: .trailing)
            Text("\(Int(row.sales.rounded()))")
                .font(.caption).frame(width: 56, alignment: .trailing)
            Text("\(Int(row.recharge.rounded()))")
                .font(.caption).frame(width: 56, alignment: .trailing)
            Text("\(row.issued)")
                .font(.caption).frame(width: 40, alignment: .trailing)
            Text("\(row.redeemed)")
                .font(.caption).frame(width: 40, alignment: .trailing)
            Text("\(row.active)")
                .font(.caption).frame(width: 36, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }

    private var sortedDaily: [StatsDailyRow] {
        let rows = data.dailyRows
        let sorted: [StatsDailyRow]
        switch dailySortCol {
        case 1: sorted = rows.sorted { dailySortAsc ? $0.newMembers < $1.newMembers : $0.newMembers > $1.newMembers }
        case 2: sorted = rows.sorted { dailySortAsc ? $0.sales < $1.sales : $0.sales > $1.sales }
        case 3: sorted = rows.sorted { dailySortAsc ? $0.recharge < $1.recharge : $0.recharge > $1.recharge }
        case 4: sorted = rows.sorted { dailySortAsc ? $0.issued < $1.issued : $0.issued > $1.issued }
        case 5: sorted = rows.sorted { dailySortAsc ? $0.redeemed < $1.redeemed : $0.redeemed > $1.redeemed }
        case 6: sorted = rows.sorted { dailySortAsc ? $0.active < $1.active : $0.active > $1.active }
        default: sorted = rows.sorted { dailySortAsc ? $0.day < $1.day : $0.day > $1.day }
        }
        return sorted
    }

    private var dailyTotalPages: Int {
        max(1, (sortedDaily.count + 9) / 10)
    }

    private var sortedDailyPage: [StatsDailyRow] {
        let page = min(max(dailyPage, 1), dailyTotalPages)
        let start = (page - 1) * 10
        let end = min(start + 10, sortedDaily.count)
        guard start < end else { return [] }
        return Array(sortedDaily[start..<end])
    }
}

// MARK: - Data

struct StatsHourBucket {
    let count: Int64
    let amount: Double
}

struct StatsTierRow {
    let name: String
    let count: Int64
    let spent: Double
}

struct StatsPayRow {
    let method: String
    let amount: Double
}

struct StatsGiftRow {
    let name: String
    let count: Int64
}

struct StatsDailyRow {
    let day: String
    let newMembers: Int64
    let sales: Double
    let recharge: Double
    let issued: Int64
    let redeemed: Int64
    let active: Int64
}

/// All Statistics values for one range, read from the DB. Query shapes
/// mirror Android `Store` range helpers (same SQL, same date rules).
struct StatsData {
    let currency: String
    let sales: Double
    let salesVs: String
    let recharge: Double
    let rechargeVs: String
    let newMembers: Int64
    let newMembersVs: String
    let redeemed: Int64
    let redeemedVs: String
    let orders: Int64
    let activeMembers: Int64
    let repeatRate: String
    let redeemRate: String
    let avgOrder: Double
    let daily: [(label: String, amount: Double)]
    let dailyTotal: Double
    let hours: [StatsHourBucket]
    let tiers: [StatsTierRow]
    let pays: [StatsPayRow]
    let couponsIssued: Int64
    let couponsUsed: Int64
    let couponRate: String
    let gifts: [StatsGiftRow]
    let dailyRows: [StatsDailyRow]

    static let empty = StatsData(
        currency: "$", sales: 0, salesVs: "0.0%", recharge: 0, rechargeVs: "0.0%",
        newMembers: 0, newMembersVs: "0.0%", redeemed: 0, redeemedVs: "0.0%",
        orders: 0, activeMembers: 0, repeatRate: "0.0%", redeemRate: "0.0%",
        avgOrder: 0, daily: [], dailyTotal: 0, hours: [], tiers: [], pays: [],
        couponsIssued: 0, couponsUsed: 0, couponRate: "0.0%", gifts: [], dailyRows: [])

    func money(_ amount: Double) -> String {
        DashboardData.money(amount, currency: currency)
    }

    func moneyTrim(_ amount: Double) -> String {
        DashboardData.moneyTrim(amount, currency: currency)
    }

    /// Percent change vs the previous equal-length period, like Android
    /// `StatisticsPage.pctText`.
    static func pctText(_ cur: Double, _ prev: Double) -> String {
        if prev == 0 { return cur == 0 ? "0.0%" : "+100.0%" }
        return String(format: "%+.1f%%", (cur - prev) / prev * 100)
    }

    static func pct(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    /// Payment-method display name, mirroring Android `payName`.
    static func payName(_ method: String) -> String {
        switch method {
        case "现金": return L10n.string("pay_cash")
        case "微信": return L10n.string("pay_wechat")
        case "支付宝": return L10n.string("pay_alipay")
        case "银行卡": return L10n.string("pay_card")
        case "储值余额": return L10n.string("pay_balance")
        case "": return L10n.string("pay_other")
        default: return method
        }
    }

    static func load(db: Database, start: String, end: String) -> StatsData {
        let currency = db.settingValue("currency", default: "$")
        let prev = AppDates.prevRange(start, end)

        func sumTx(_ types: [String], _ s: String, _ e: String) -> Double {
            let placeholders = types.map { _ in "?" }.joined(separator: ",")
            let rows = db.query(
                "SELECT COALESCE(SUM(amount),0) AS v FROM transactions WHERE type IN (\(placeholders)) AND date(created_at) >= ? AND date(created_at) <= ?",
                bindings: types.map { SQLiteValue.text($0) } + [.text(s), .text(e)])
            return rows.first?.real("v") ?? 0
        }

        func countMembers(_ s: String, _ e: String) -> Int64 {
            db.query(
                "SELECT COUNT(*) AS c FROM members WHERE date(created_at) >= ? AND date(created_at) <= ?",
                bindings: [.text(s), .text(e)]).first?.int("c") ?? 0
        }

        func pointsIssued(_ s: String, _ e: String) -> Int64 {
            db.query(
                "SELECT COALESCE(SUM(points_change),0) AS v FROM transactions WHERE points_change > 0 AND date(created_at) >= ? AND date(created_at) <= ?",
                bindings: [.text(s), .text(e)]).first?.int("v") ?? 0
        }

        func pointsRedeemed(_ s: String, _ e: String) -> Int64 {
            db.query(
                "SELECT COALESCE(-SUM(points_change),0) AS v FROM transactions WHERE points_change < 0 AND date(created_at) >= ? AND date(created_at) <= ?",
                bindings: [.text(s), .text(e)]).first?.int("v") ?? 0
        }

        func orders(_ s: String, _ e: String) -> Int64 {
            db.query(
                "SELECT COUNT(*) AS c FROM transactions WHERE type IN ('checkout','earn') AND date(created_at) >= ? AND date(created_at) <= ?",
                bindings: [.text(s), .text(e)]).first?.int("c") ?? 0
        }

        func activeMembers(_ s: String, _ e: String) -> Int64 {
            db.query(
                "SELECT COUNT(DISTINCT member_id) AS c FROM transactions WHERE member_id IS NOT NULL AND date(created_at) >= ? AND date(created_at) <= ?",
                bindings: [.text(s), .text(e)]).first?.int("c") ?? 0
        }

        func repeatMembers(_ s: String, _ e: String) -> Int64 {
            db.query(
                "SELECT COUNT(*) AS c FROM (SELECT member_id FROM transactions WHERE type IN ('checkout','earn') AND member_id IS NOT NULL AND date(created_at) >= ? AND date(created_at) <= ? GROUP BY member_id HAVING COUNT(*) >= 2)",
                bindings: [.text(s), .text(e)]).first?.int("c") ?? 0
        }

        let sales = sumTx(["checkout", "earn"], start, end)
        let recharge = sumTx(["recharge"], start, end)
        let newMembers = countMembers(start, end)
        let redeemed = pointsRedeemed(start, end)
        let issued = pointsIssued(start, end)
        let orderCount = orders(start, end)
        let active = activeMembers(start, end)
        let repeatCount = repeatMembers(start, end)

        // Trend: every day in range (Android dailySales, zero-filled).
        var daily: [(label: String, amount: Double)] = []
        var dailyTotal: Double = 0
        var dailySalesByDay: [String: Double] = [:]
        for row in db.query(
            "SELECT date(created_at) AS d, COALESCE(SUM(amount),0) AS v FROM transactions WHERE type IN ('checkout','earn') AND date(created_at) >= ? AND date(created_at) <= ? GROUP BY date(created_at) ORDER BY date(created_at)",
            bindings: [.text(start), .text(end)]) {
            dailySalesByDay[row.text("d")] = row.real("v")
        }
        for day in AppDates.daysInRange(start, end) {
            let amount = dailySalesByDay[day] ?? 0
            daily.append((label: String(day.suffix(2)), amount: amount))
            dailyTotal += amount
        }

        // Hour buckets: 6 slots 9–11 … 19–21 (Android hourlyBuckets).
        var hours = Array(repeating: StatsHourBucket(count: 0, amount: 0), count: 6)
        for row in db.query(
            "SELECT CAST(strftime('%H', created_at) AS INTEGER) AS h, COUNT(*) AS c, COALESCE(SUM(amount),0) AS v FROM transactions WHERE type IN ('checkout','earn') AND date(created_at) >= ? AND date(created_at) <= ? GROUP BY 1",
            bindings: [.text(start), .text(end)]) {
            let hour = Int(row.int("h"))
            let idx = (hour - 9) / 2
            if idx >= 0 && idx < 6 {
                hours[idx] = StatsHourBucket(count: hours[idx].count + row.int("c"),
                                             amount: hours[idx].amount + row.real("v"))
            }
        }

        // Tier analysis: members per tier (tierForSpent) + their spend.
        let tiers = db.query("SELECT name, min_spent, color FROM tiers ORDER BY min_spent ASC")
            .map { (name: $0.text("name"), minSpent: $0.real("min_spent"), color: $0.text("color")) }
        func tierIndex(for spent: Double) -> Int? {
            var best: Int? = nil
            for (index, tier) in tiers.enumerated() where tier.minSpent <= spent {
                best = index
            }
            if best == nil && !tiers.isEmpty { return 0 }
            return best
        }
        var tierCounts = Array(repeating: Int64(0), count: tiers.count)
        var tierSpent = Array(repeating: 0.0, count: tiers.count)
        for member in db.query("SELECT total_spent FROM members") {
            if let idx = tierIndex(for: member.real("total_spent")) {
                tierCounts[idx] += 1
                tierSpent[idx] += member.real("total_spent")
            }
        }
        let tierStats = tiers.enumerated().map { index, tier in
            StatsTierRow(name: tier.name, count: tierCounts[index], spent: tierSpent[index])
        }

        // Payment methods, biggest first (Android payStats).
        let pays = db.query(
            "SELECT COALESCE(pay_method,'') AS m, COALESCE(SUM(amount),0) AS v FROM transactions WHERE type IN ('checkout','earn') AND date(created_at) >= ? AND date(created_at) <= ? GROUP BY pay_method ORDER BY 2 DESC",
            bindings: [.text(start), .text(end)])
            .map { StatsPayRow(method: $0.text("m"), amount: $0.real("v")) }

        // Coupons issued / used in range (Android couponStats).
        let couponRows = db.query(
            "SELECT (SELECT COUNT(*) FROM member_coupons WHERE date(issued_at) >= ? AND date(issued_at) <= ?) AS c0, (SELECT COUNT(*) FROM member_coupons WHERE status='used' AND date(used_at) >= ? AND date(used_at) <= ?) AS c1",
            bindings: [.text(start), .text(end), .text(start), .text(end)])
        let couponsIssued = couponRows.first?.int("c0") ?? 0
        let couponsUsed = couponRows.first?.int("c1") ?? 0

        // Gift redemptions Top 5 by ref_id (Android giftTop).
        let gifts = db.query(
            "SELECT t.ref_id AS r, g.name AS n, COUNT(*) AS c FROM transactions t LEFT JOIN gifts g ON g.id = t.ref_id WHERE t.type='exchange' AND t.ref_id > 0 AND date(t.created_at) >= ? AND date(t.created_at) <= ? GROUP BY t.ref_id ORDER BY c DESC LIMIT 5",
            bindings: [.text(start), .text(end)])
            .compactMap { row -> StatsGiftRow? in
                let name = row.text("n")
                guard !name.isEmpty else { return nil }
                return StatsGiftRow(name: name, count: row.int("c"))
            }

        // Daily detail rows (Android dailyDetail).
        var dailyRows: [StatsDailyRow] = []
        for day in AppDates.daysInRange(start, end) {
            dailyRows.append(StatsDailyRow(
                day: day,
                newMembers: countMembers(day, day),
                sales: sumTx(["checkout", "earn"], day, day),
                recharge: sumTx(["recharge"], day, day),
                issued: pointsIssued(day, day),
                redeemed: pointsRedeemed(day, day),
                active: activeMembers(day, day)))
        }

        return StatsData(
            currency: currency,
            sales: sales,
            salesVs: pctText(sales, sumTx(["checkout", "earn"], prev.0, prev.1)),
            recharge: recharge,
            rechargeVs: pctText(recharge, sumTx(["recharge"], prev.0, prev.1)),
            newMembers: newMembers,
            newMembersVs: pctText(Double(newMembers), Double(countMembers(prev.0, prev.1))),
            redeemed: redeemed,
            redeemedVs: pctText(Double(redeemed), Double(pointsRedeemed(prev.0, prev.1))),
            orders: orderCount,
            activeMembers: active,
            repeatRate: active > 0 ? pct(Double(repeatCount) * 100.0 / Double(active)) : "0.0%",
            redeemRate: issued > 0 ? pct(Double(redeemed) * 100.0 / Double(issued)) : "0.0%",
            avgOrder: orderCount > 0 ? sales / Double(orderCount) : 0,
            daily: daily, dailyTotal: dailyTotal,
            hours: hours, tiers: tierStats, pays: pays,
            couponsIssued: couponsIssued, couponsUsed: couponsUsed,
            couponRate: couponsIssued > 0
                ? pct(Double(couponsUsed) * 100.0 / Double(couponsIssued)) : "0.0%",
            gifts: gifts, dailyRows: dailyRows)
    }
}
