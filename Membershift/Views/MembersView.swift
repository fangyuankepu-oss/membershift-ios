import SwiftUI

/// Members — mirrors Android `MembersPage`.
///
/// - List: search (name / phone), segment tabs (全部 / 新客 / 沉睡会员 /
///   高价值会员 / 积分将过期, with counts), tag filter, add button.
/// - Row: name, tier badge (DB hex colour), 将过期 badge, subline
///   (phone · points · balance · total spent).
/// - Tap a row for the 360° detail (tier progress, expiring points,
///   stats, info, preferred Top 3, tags, referrer, coupons held,
///   recent 8 transactions, edit / delete).
/// - Add/edit form: name, phone, optional email, optional 4-digit PIN
///   (salt + hash, Android fix5), gender, birthday, referrer picker,
///   note; validations mirror Android (name/phone required, phone
///   unique, email shape, PIN exactly 4 digits).
/// - Delete (manager only): confirm, then the manager password must be
///   re-entered (Android fix6); cascade deletes coupons / ledger / tags
///   and clears referrer_id on other members.
///
/// Deferred to a later batch (reported, not silently dropped):
/// - 分群发券 (bulk coupon issue to a segment) — needs the Coupons page.
/// - 打印积分记录 (print member record) — no printer on iOS yet.
struct MembersView: View {
    @EnvironmentObject private var appState: AppState

    @State private var searchText = ""
    @State private var segment = "all"
    @State private var tagFilter = ""
    @State private var currency = "$"
    @State private var tiers: [MemberTier] = []
    @State private var members: [MemberRow] = []
    @State private var segNew: Set<Int64> = []
    @State private var segDormant: Set<Int64> = []
    @State private var segVip: Set<Int64> = []
    @State private var segExpiring: Set<Int64> = []
    @State private var allTags: [String] = []
    @State private var selectedMember: MemberRow?
    @State private var showingForm = false
    @State private var formMember: MemberRow?

    private static let segments = ["all", "new", "dormant", "vip", "expiring"]
    private static let segmentKeys = [
        "mem_segment_all", "mem_segment_new", "mem_segment_dormant",
        "mem_segment_vip", "mem_segment_expiring",
    ]

    var body: some View {
        VStack(spacing: 0) {
            searchField
            segmentBar
            filterRow
            if filtered.isEmpty {
                Spacer()
                Text(L10n.string("mem_empty"))
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(filtered) { member in
                        Button { selectedMember = member } label: {
                            memberRow(member)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color(.systemGroupedBackground))
        .onAppear { reload() }
        .sheet(item: $selectedMember) { member in
            MemberDetailView(
                memberId: member.id,
                isManager: appState.currentUser?.isManager ?? false,
                username: appState.currentUser?.username ?? "admin",
                onChanged: { reload() })
        }
        .sheet(isPresented: $showingForm) {
            MemberFormView(member: formMember, allMembers: members,
                           onSaved: { reload() })
        }
    }

    private func reload() {
        let db = Database.shared
        currency = db.settingValue("currency", default: "$")
        tiers = MemberStore.loadTiers(db: db)
        members = MemberStore.loadMembers(db: db)
        let sets = MemberStore.segmentSets(db: db)
        segNew = sets.new
        segDormant = sets.dormant
        segVip = sets.vip
        segExpiring = sets.expiring
        allTags = MemberStore.getAllTags(db: db)
    }

    private var filtered: [MemberRow] {
        members.filter { member in
            if !searchText.isEmpty {
                let q = searchText
                let nameHit = member.name.localizedCaseInsensitiveContains(q)
                let phoneHit = member.phone.contains(q)
                if !nameHit && !phoneHit { return false }
            }
            switch segment {
            case "new": if !segNew.contains(member.id) { return false }
            case "dormant": if !segDormant.contains(member.id) { return false }
            case "vip": if !segVip.contains(member.id) { return false }
            case "expiring": if !segExpiring.contains(member.id) { return false }
            default: break
            }
            if !tagFilter.isEmpty {
                let tags = MemberStore.getMemberTags(db: Database.shared, memberId: member.id)
                if !tags.contains(tagFilter) { return false }
            }
            return true
        }
    }

    private var segmentCounts: [String: Int] {
        [
            "all": members.count,
            "new": segNew.count,
            "dormant": segDormant.count,
            "vip": segVip.count,
            "expiring": segExpiring.count,
        ]
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField(L10n.string("mem_search_hint"), text: $searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var segmentBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.segments.indices, id: \.self) { index in
                    let seg = Self.segments[index]
                    let selected = segment == seg
                    Button {
                        segment = seg
                    } label: {
                        Text(String(format: L10n.string("mem_segment_count_fmt"),
                                    L10n.string(Self.segmentKeys[index]),
                                    segmentCounts[seg] ?? 0))
                            .font(.subheadline)
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selected ? Brand.deepGreen : Color(.systemBackground))
                            .foregroundColor(selected ? .white : Color(.label))
                            .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
    }

    private var filterRow: some View {
        HStack(spacing: 12) {
            Menu {
                Button(L10n.string("mem_tag_all")) { tagFilter = "" }
                ForEach(allTags, id: \.self) { tag in
                    Button(tag) { tagFilter = tag }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(tagFilter.isEmpty ? L10n.string("mem_tag_all") : tagFilter)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
                .cornerRadius(10)
            }
            Spacer()
            Button(L10n.string("mem_add")) {
                formMember = nil
                showingForm = true
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.deepGreen)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func memberRow(_ member: MemberRow) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(member.name)
                        .font(.headline)
                        .lineLimit(1)
                    if let tier = MemberStore.tierForSpent(tiers: tiers,
                                                            spent: member.totalSpent) {
                        Text(tier.name)
                            .font(.caption)
                            .bold()
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(hex: tier.color))
                            .cornerRadius(8)
                    }
                    if segExpiring.contains(member.id) {
                        Text(L10n.string("mem_expiring_badge"))
                            .font(.caption)
                            .bold()
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Brand.gold)
                            .cornerRadius(8)
                    }
                }
                Text(member.phone + " · "
                     + String(format: L10n.string("mem_points_fmt"), Int(member.points))
                     + " · " + String(format: L10n.string("mem_balance_fmt"),
                                      DashboardData.moneyTrim(member.balance, currency: currency))
                     + " · " + String(format: L10n.string("mem_spent_fmt"),
                                      DashboardData.moneyTrim(member.totalSpent, currency: currency)))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Data layer (mirrors Android Store member helpers)

struct MemberTier {
    let id: Int64
    let name: String
    let minSpent: Double
    let discount: Double
    let multiplier: Double
    let color: String
}

struct MemberRow: Identifiable {
    let id: Int64
    var name: String
    var phone: String
    var email: String
    var pinSalt: String
    var pinHash: String
    var gender: String
    var birthday: String
    var note: String
    var points: Int64
    var balance: Double
    var totalSpent: Double
    var referrerId: Int64
    var referralRewarded: Int64
    var createdAt: String
}

enum MemberStore {
    static func rowFromDBRow(_ row: DBRow) -> MemberRow {
        MemberRow(
            id: row.int("id"), name: row.text("name"), phone: row.text("phone"),
            email: row.text("email"), pinSalt: row.text("pin_salt"),
            pinHash: row.text("pin_hash"), gender: row.text("gender"),
            birthday: row.text("birthday"), note: row.text("note"),
            points: row.int("points"), balance: row.real("balance"),
            totalSpent: row.real("total_spent"),
            referrerId: row.int("referrer_id") == 0 ? -1 : row.int("referrer_id"),
            referralRewarded: row.int("referral_rewarded"),
            createdAt: row.text("created_at"))
    }

    static func loadMembers(db: Database) -> [MemberRow] {
        db.query("SELECT * FROM members ORDER BY created_at DESC")
            .map { rowFromDBRow($0) }
    }

    static func memberById(db: Database, id: Int64) -> MemberRow? {
        db.query("SELECT * FROM members WHERE id = ?", bindings: [.int(id)])
            .first.map { rowFromDBRow($0) }
    }

    static func phoneExists(db: Database, phone: String, excludeId: Int64) -> Bool {
        let rows = db.query(
            "SELECT COUNT(*) AS c FROM members WHERE phone = ? AND id <> ?",
            bindings: [.text(phone), .int(excludeId)])
        return (rows.first?.int("c") ?? 0) > 0
    }

    /// PIN format: exactly 4 digits (Android fix5 `isValidPin`).
    static func isValidPin(_ pin: String) -> Bool {
        pin.count == 4 && pin.allSatisfy { $0.isNumber && $0.isASCII }
    }

    /// Minimal email check (Android fix4): one @, text on both sides, no spaces.
    static func isValidEmail(_ email: String) -> Bool {
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty
            && !email.contains(" ")
    }

    static func loadTiers(db: Database) -> [MemberTier] {
        db.query("SELECT id, name, min_spent, discount, multiplier, color FROM tiers ORDER BY min_spent ASC")
            .map {
                MemberTier(id: $0.int("id"), name: $0.text("name"),
                           minSpent: $0.real("min_spent"), discount: $0.real("discount"),
                           multiplier: $0.real("multiplier"), color: $0.text("color"))
            }
    }

    /// Highest tier whose threshold the spend reaches, else the first tier
    /// (Android `tierForSpent`).
    static func tierForSpent(tiers: [MemberTier], spent: Double) -> MemberTier? {
        var best: MemberTier? = nil
        for tier in tiers where tier.minSpent <= spent { best = tier }
        if best == nil { return tiers.first }
        return best
    }

    /// Next tier above the spend, or nil at the top (Android `nextTier`).
    static func nextTier(tiers: [MemberTier], spent: Double) -> MemberTier? {
        tiers.first { $0.minSpent > spent }
    }

    /// Discount display: 0.95 -> "9.5", 1.0 -> nil (Android `discountText`).
    static func discountText(_ discount: Double) -> String? {
        guard discount < 1 else { return nil }
        let zhe = discount * 10
        if zhe == floor(zhe) { return String(format: "%.0f", zhe) }
        return String(format: "%.1f", zhe)
    }

    static func insertMember(db: Database, member: MemberRow) -> Int64 {
        let id = db.nextId("member")
        let ok = db.execute(
            "INSERT INTO members (id, name, phone, email, pin_salt, pin_hash, gender, birthday, note, points, balance, total_spent, referrer_id, referral_rewarded, created_at) VALUES (?, ?, ?, ?, '', '', ?, ?, ?, 0, 0, 0, ?, 0, ?)",
            bindings: [.int(id), .text(member.name), .text(member.phone),
                       .text(member.email), .text(member.gender), .text(member.birthday),
                       .text(member.note),
                       member.referrerId > 0 ? .int(member.referrerId) : .null,
                       .text(AppDates.now())])
        return ok ? id : -1
    }

    static func updateMember(db: Database, member: MemberRow) -> Bool {
        db.execute(
            "UPDATE members SET name = ?, phone = ?, email = ?, gender = ?, birthday = ?, note = ?, referrer_id = ? WHERE id = ?",
            bindings: [.text(member.name), .text(member.phone), .text(member.email),
                       .text(member.gender), .text(member.birthday), .text(member.note),
                       member.referrerId > 0 ? .int(member.referrerId) : .null,
                       .int(member.id)])
    }

    /// Sets the member PIN (salt + sha256(salt + "::" + pin), Android fix5).
    /// Empty pin clears it. Returns false if a non-empty pin is not 4 digits.
    static func setMemberPin(db: Database, memberId: Int64, pin: String) -> Bool {
        let p = pin.trimmingCharacters(in: .whitespaces)
        if p.isEmpty {
            return db.execute(
                "UPDATE members SET pin_salt = '', pin_hash = '' WHERE id = ?",
                bindings: [.int(memberId)])
        }
        guard isValidPin(p) else { return false }
        let salt = Auth.makeSalt()
        return db.execute(
            "UPDATE members SET pin_salt = ?, pin_hash = ? WHERE id = ?",
            bindings: [.text(salt), .text(Auth.hashPassword(p, salt: salt)), .int(memberId)])
    }

    /// Deletes a member (manager only): cascade deletes coupons / ledger /
    /// tags and clears referrer_id on other members (Android
    /// `deleteMemberCascade`), all in one transaction.
    static func deleteMemberCascade(db: Database, memberId: Int64) -> Bool {
        guard db.execute("BEGIN TRANSACTION") else { return false }
        var ok = true
        ok = ok && db.execute("DELETE FROM member_coupons WHERE member_id = ?",
                              bindings: [.int(memberId)])
        ok = ok && db.execute("DELETE FROM points_ledger WHERE member_id = ?",
                              bindings: [.int(memberId)])
        ok = ok && db.execute("DELETE FROM member_tags WHERE member_id = ?",
                              bindings: [.int(memberId)])
        ok = ok && db.execute("DELETE FROM members WHERE id = ?",
                              bindings: [.int(memberId)])
        ok = ok && db.execute("UPDATE members SET referrer_id = NULL WHERE referrer_id = ?",
                              bindings: [.int(memberId)])
        if ok {
            ok = db.execute("COMMIT")
        } else {
            db.execute("ROLLBACK")
        }
        return ok
    }

    static func getAllTags(db: Database) -> [String] {
        db.query("SELECT DISTINCT tag FROM member_tags ORDER BY tag")
            .map { $0.text("tag") }
    }

    static func getMemberTags(db: Database, memberId: Int64) -> [String] {
        db.query("SELECT tag FROM member_tags WHERE member_id = ? ORDER BY tag ASC",
                 bindings: [.int(memberId)])
            .map { $0.text("tag") }
    }

    static func addTag(db: Database, memberId: Int64, tag: String) -> Bool {
        let t = tag.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return false }
        return db.execute(
            "INSERT OR IGNORE INTO member_tags (member_id, tag) VALUES (?, ?)",
            bindings: [.int(memberId), .text(t)])
    }

    static func removeTag(db: Database, memberId: Int64, tag: String) -> Bool {
        db.execute("DELETE FROM member_tags WHERE member_id = ? AND tag = ?",
                   bindings: [.int(memberId), .text(tag)])
    }

    /// Points of this member expiring within `withinDays` days
    /// (Android `expiringForMember`).
    static func expiringForMember(db: Database, memberId: Int64,
                                  withinDays: Int = 30) -> (points: Int64, nearestDate: String) {
        let today = AppDates.today()
        let limit = AppDates.addDays(today, withinDays)
        let rows = db.query(
            "SELECT COALESCE(SUM(points_total - points_used),0) AS p, MIN(expiry_date) AS d FROM points_ledger WHERE member_id = ? AND expiry_date <> '' AND expiry_date >= ? AND expiry_date <= ? AND (points_total - points_used) > 0",
            bindings: [.int(memberId), .text(today), .text(limit)])
        return (rows.first?.int("p") ?? 0, rows.first?.text("d") ?? "")
    }

    /// Segment id sets (Android `segmentNew/Dormant/Vip/Expiring`).
    static func segmentSets(db: Database) -> (new: Set<Int64>, dormant: Set<Int64>,
                                               vip: Set<Int64>, expiring: Set<Int64>) {
        let today = AppDates.today()
        let newRows = db.query(
            "SELECT id FROM members WHERE date(created_at) >= ?",
            bindings: [.text(AppDates.addDays(today, -30))])
        let dormantRows = db.query(
            "SELECT member_id AS id, MAX(date(created_at)) AS d FROM transactions WHERE type = 'checkout' AND member_id IS NOT NULL GROUP BY member_id HAVING MAX(date(created_at)) < ?",
            bindings: [.text(AppDates.addDays(today, -90))])
        let expiringRows = db.query(
            "SELECT DISTINCT member_id AS id FROM points_ledger WHERE expiry_date <> '' AND expiry_date >= ? AND expiry_date <= ? AND (points_total - points_used) > 0",
            bindings: [.text(today), .text(AppDates.addDays(today, 30))])
        // High-value: top 20% by total spent (Android segmentVip).
        let spent = db.query("SELECT id, total_spent FROM members WHERE total_spent > 0")
            .map { (id: $0.int("id"), spent: $0.real("total_spent")) }
        var vip: Set<Int64> = []
        if !spent.isEmpty {
            let sorted = spent.map { $0.spent }.sorted()
            var idx = Int(ceil(Double(sorted.count) * 0.8)) - 1
            if idx < 0 { idx = 0 }
            let threshold = sorted[idx]
            for row in spent where row.spent >= threshold { vip.insert(row.id) }
        }
        return (Set(newRows.map { $0.int("id") }),
                Set(dormantRows.map { $0.int("id") }),
                vip,
                Set(expiringRows.map { $0.int("id") }))
    }

    static func visitCount(db: Database, memberId: Int64) -> Int64 {
        db.query("SELECT COUNT(*) AS c FROM transactions WHERE type = 'checkout' AND member_id = ?",
                 bindings: [.int(memberId)]).first?.int("c") ?? 0
    }

    /// Preferred categories / products Top 3 by checkout line amount
    /// (Android `prefCategories` / `prefProducts`).
    static func prefAggregate(db: Database, memberId: Int64, limit: Int,
                              byCategory: Bool) -> [(name: String, amount: Double)] {
        var agg: [String: Double] = [:]
        for row in db.query(
            "SELECT items FROM transactions WHERE type = 'checkout' AND member_id = ?",
            bindings: [.int(memberId)]) {
            let itemsText = row.text("items")
            guard let data = itemsText.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                continue
            }
            for item in arr {
                let key = (byCategory ? item["category"] : item["name"]) as? String ?? ""
                guard !key.isEmpty else { continue }
                let price = (item["price"] as? NSNumber)?.doubleValue ?? 0
                let qty = (item["qty"] as? NSNumber)?.doubleValue ?? 1
                agg[key, default: 0] += price * qty
            }
        }
        return agg.sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (name: $0.key, amount: $0.value) }
    }

    struct MemberCouponRow {
        let name: String
        let status: String
        let expiresAt: String
    }

    static func couponsOfMember(db: Database, memberId: Int64) -> [MemberCouponRow] {
        db.query(
            "SELECT COALESCE(cp.name,'') AS n, mc.status AS s, mc.expires_at AS e FROM member_coupons mc LEFT JOIN coupons cp ON cp.id = mc.coupon_id WHERE mc.member_id = ? ORDER BY mc.issued_at DESC",
            bindings: [.int(memberId)])
            .map { MemberCouponRow(name: $0.text("n"), status: $0.text("s"),
                                   expiresAt: $0.text("e")) }
    }

    static func referredCount(db: Database, memberId: Int64) -> Int64 {
        db.query("SELECT COUNT(*) AS c FROM members WHERE referrer_id = ?",
                 bindings: [.int(memberId)]).first?.int("c") ?? 0
    }

    struct MemberTxRow {
        let timeLabel: String
        let typeName: String
        let rightText: String
    }

    static func txByMember(db: Database, memberId: Int64, limit: Int,
                           currency: String) -> [MemberTxRow] {
        db.query(
            "SELECT type, amount, points_change, created_at FROM transactions WHERE member_id = ? ORDER BY created_at DESC LIMIT ?",
            bindings: [.int(memberId), .int(Int64(limit))])
            .map { row in
                let createdAt = row.text("created_at")
                let timeLabel = createdAt.count >= 16
                    ? String(createdAt.dropFirst(5).prefix(11)) : createdAt
                let amount = row.real("amount")
                let pointsChange = row.int("points_change")
                var right = DashboardData.moneyTrim(amount, currency: currency)
                if pointsChange != 0 {
                    let sign = pointsChange > 0 ? "+" : ""
                    right += " " + sign + String(format: L10n.string("mem_points_fmt"),
                                                 Int(pointsChange))
                }
                return MemberTxRow(timeLabel: timeLabel,
                                   typeName: txTypeName(row.text("type")),
                                   rightText: right)
            }
    }
}

/// Transaction type name, mirroring Android `DashboardPage.txTypeName`
/// (same mapping as DashboardView's private copy).
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
    /// Same helper as DashboardView's private copy (file-scoped).
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

// MARK: - Member detail (360°, mirrors Android MembersPage.showDetail)

struct MemberDetailView: View {
    let memberId: Int64
    let isManager: Bool
    let username: String
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var member: MemberRow?
    @State private var currency = "$"
    @State private var tags: [String] = []
    @State private var newTag = ""
    @State private var showingForm = false
    @State private var showingDeleteConfirm = false
    @State private var showingManagerPw = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let member {
                    detailContent(member)
                } else {
                    Text(L10n.string("mem_empty"))
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L10n.string("mem_detail_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("mem_close")) { dismiss() }
                }
            }
            .onAppear { reload() }
            .sheet(isPresented: $showingForm) {
                if let member {
                    MemberFormView(member: member, allMembers: MemberStore.loadMembers(db: Database.shared)) {
                        reload()
                        onChanged()
                    }
                }
            }
            .sheet(isPresented: $showingManagerPw) {
                ManagerPasswordView(username: username) {
                    _ = MemberStore.deleteMemberCascade(db: Database.shared, memberId: memberId)
                    onChanged()
                    dismiss()
                }
            }
            .alert(L10n.string("mem_delete"), isPresented: $showingDeleteConfirm) {
                Button(L10n.string("common_delete"), role: .destructive) {
                    showingManagerPw = true
                }
                Button(L10n.string("common_cancel"), role: .cancel) {}
            } message: {
                if let member {
                    Text(String(format: L10n.string("mem_delete_confirm"), member.name))
                }
            }
        }
    }

    private func reload() {
        let db = Database.shared
        currency = db.settingValue("currency", default: "$")
        member = MemberStore.memberById(db: db, id: memberId)
        tags = MemberStore.getMemberTags(db: db, memberId: memberId)
    }

    private func detailContent(_ m: MemberRow) -> some View {
        let db = Database.shared
        let tiers = MemberStore.loadTiers(db: db)
        let tier = MemberStore.tierForSpent(tiers: tiers, spent: m.totalSpent)
        let next = MemberStore.nextTier(tiers: tiers, spent: m.totalSpent)
        let expiring = MemberStore.expiringForMember(db: db, memberId: m.id)
        let visits = MemberStore.visitCount(db: db, memberId: m.id)
        let avg = visits > 0 ? m.totalSpent / Double(visits) : 0
        let referrerName = m.referrerId > 0
            ? (MemberStore.memberById(db: db, id: m.referrerId)?.name ?? "")
            : ""
        let referred = MemberStore.referredCount(db: db, memberId: m.id)
        let coupons = MemberStore.couponsOfMember(db: db, memberId: m.id)
        let txs = MemberStore.txByMember(db: db, memberId: m.id, limit: 8, currency: currency)
        let prefCats = MemberStore.prefAggregate(db: db, memberId: m.id, limit: 3, byCategory: true)
        let prefProducts = MemberStore.prefAggregate(db: db, memberId: m.id, limit: 3, byCategory: false)

        return VStack(spacing: 12) {
            detailCard {
                HStack(spacing: 12) {
                    Text(m.name.isEmpty ? "?" : String(m.name.prefix(1)))
                        .font(.title)
                        .bold()
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Brand.deepGreen)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(m.name)
                                .font(.title3)
                                .bold()
                            if let tier {
                                Text(tier.name)
                                    .font(.caption)
                                    .bold()
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color(hex: tier.color))
                                    .cornerRadius(8)
                            }
                        }
                        if let tier {
                            let discount = MemberStore.discountText(tier.discount)
                            Text(tier.name + " · "
                                 + (discount == nil
                                    ? L10n.string("mem_discount_none")
                                    : String(format: L10n.string("mem_discount_fmt"), discount!))
                                 + " · " + String(format: L10n.string("mem_multiplier_fmt"),
                                                  tier.multiplier == floor(tier.multiplier)
                                                    ? String(format: "%.0f", tier.multiplier)
                                                    : String(format: "%.1f", tier.multiplier)))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Text(m.phone)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                // Tier progress.
                if let next {
                    let span = next.minSpent - (tier?.minSpent ?? 0)
                    let progress = span > 0
                        ? max(0, min(1, (m.totalSpent - (tier?.minSpent ?? 0)) / span)) : 1
                    ProgressView(value: progress)
                        .tint(Brand.deepGreen)
                    Text(String(format: L10n.string("mem_tier_progress"), next.name,
                                DashboardData.moneyTrim(next.minSpent - m.totalSpent,
                                                        currency: currency)))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text(L10n.string("mem_tier_top"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                // Expiring points.
                Text(expiring.points > 0
                     ? String(format: L10n.string("mem_expiring_points"),
                              Int(expiring.points), expiring.nearestDate)
                     : L10n.string("mem_no_expiring"))
                    .font(.subheadline)
                    .foregroundColor(expiring.points > 0 ? .red : .secondary)
            }

            detailCard {
                detailRow(labelKey: "mem_total_spent_label",
                          value: DashboardData.moneyTrim(m.totalSpent, currency: currency))
                detailRow(labelKey: "mem_points_label",
                          value: String(format: L10n.string("mem_points_fmt"), Int(m.points)))
                detailRow(labelKey: "mem_balance_label",
                          value: DashboardData.moneyTrim(m.balance, currency: currency))
                Text(String(format: L10n.string("mem_visits"), Int(visits))
                     + " · " + String(format: L10n.string("mem_avg_order"),
                                      DashboardData.moneyTrim(avg, currency: currency)))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            detailCard {
                detailRow(labelKey: "mem_gender_label", value: genderName(m.gender))
                detailRow(labelKey: "mem_birthday_label",
                          value: m.birthday.isEmpty ? L10n.string("mem_birthday_none") : m.birthday)
                if !m.email.isEmpty {
                    detailRow(labelKey: "mem_email", value: m.email)
                }
                detailRow(labelKey: "mem_pin",
                          value: m.pinHash.isEmpty
                            ? L10n.string("mem_pin_unset") : L10n.string("mem_pin_set"))
                detailRow(labelKey: "mem_note_label",
                          value: m.note.isEmpty ? L10n.string("mem_referrer_none") : m.note)
            }

            detailCard {
                detailRow(labelKey: "mem_pref_cat",
                          value: prefCats.isEmpty ? L10n.string("mem_referrer_none")
                            : prefCats.map { "\($0.name) \(DashboardData.moneyTrim($0.amount, currency: currency))" }
                                .joined(separator: " · "))
                detailRow(labelKey: "mem_pref_product",
                          value: prefProducts.isEmpty ? L10n.string("mem_referrer_none")
                            : prefProducts.map { "\($0.name) \(DashboardData.moneyTrim($0.amount, currency: currency))" }
                                .joined(separator: " · "))
            }

            detailCard {
                Text(L10n.string("mem_tags"))
                    .font(.headline)
                if tags.isEmpty {
                    Text(L10n.string("mem_no_tags"))
                        .foregroundColor(.secondary)
                } else {
                    FlowChips(tags: tags) { tag in
                        _ = MemberStore.removeTag(db: Database.shared, memberId: m.id, tag: tag)
                        reload()
                        onChanged()
                    }
                }
                HStack(spacing: 8) {
                    TextField(L10n.string("mem_tag_hint"), text: $newTag)
                        .textFieldStyle(.roundedBorder)
                    Button(L10n.string("mem_add_tag")) {
                        if MemberStore.addTag(db: Database.shared, memberId: m.id, tag: newTag) {
                            newTag = ""
                            reload()
                            onChanged()
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(Brand.deepGreen)
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            detailCard {
                Text(String(format: L10n.string("mem_referrer_info"),
                            referrerName.isEmpty ? L10n.string("mem_referrer_none") : referrerName)
                     + " · " + String(format: L10n.string("mem_referred_count"), Int(referred))
                     + " · " + (m.referralRewarded == 1
                                ? L10n.string("mem_reward_done")
                                : L10n.string("mem_reward_pending")))
                    .font(.subheadline)
            }

            detailCard {
                Text(L10n.string("mem_coupons"))
                    .font(.headline)
                if coupons.isEmpty {
                    Text(L10n.string("mem_no_coupons"))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(coupons.indices, id: \.self) { index in
                        let coupon = coupons[index]
                        let today = AppDates.today()
                        let statusKey: String
                        if coupon.status == "used" {
                            statusKey = "mem_coupon_used"
                        } else if !coupon.expiresAt.isEmpty
                                    && String(coupon.expiresAt.prefix(10)) < today {
                            statusKey = "mem_coupon_expired"
                        } else {
                            statusKey = "mem_coupon_unused"
                        }
                        let expDate = coupon.expiresAt.count >= 10
                            ? String(coupon.expiresAt.prefix(10)) : coupon.expiresAt
                        Text(String(format: L10n.string("mem_coupon_fmt"),
                                    coupon.name, L10n.string(statusKey), expDate))
                            .font(.subheadline)
                            .padding(.vertical, 2)
                    }
                }
            }

            detailCard {
                Text(L10n.string("mem_recent_tx"))
                    .font(.headline)
                if txs.isEmpty {
                    Text(L10n.string("mem_no_tx"))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(txs.indices, id: \.self) { index in
                        let tx = txs[index]
                        HStack(spacing: 8) {
                            Text(tx.timeLabel + " " + tx.typeName)
                                .lineLimit(1)
                            Spacer()
                            Text(tx.rightText)
                                .lineLimit(1)
                        }
                        .font(.subheadline)
                        .padding(.vertical, 2)
                    }
                }
            }

            HStack(spacing: 12) {
                Button(L10n.string("mem_edit")) { showingForm = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.deepGreen)
                    .frame(maxWidth: .infinity)
                if isManager {
                    Button(L10n.string("mem_delete")) { showingDeleteConfirm = true }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
    }

    private func detailCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    private func detailRow(labelKey: String, value: String) -> some View {
        HStack {
            Text(L10n.string(labelKey))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .lineLimit(1)
        }
        .font(.subheadline)
        .padding(.vertical, 2)
    }

    private func genderName(_ gender: String) -> String {
        switch gender {
        case "男": return L10n.string("mem_gender_male")
        case "女": return L10n.string("mem_gender_female")
        default: return L10n.string("mem_gender_secret")
        }
    }
}

/// Wrapping tag chips with a × delete button each.
private struct FlowChips: View {
    let tags: [String]
    let onDelete: (String) -> Void

    var body: some View {
        // Simple left-aligned wrapping layout via a flexible row set.
        VStack(alignment: .leading, spacing: 8) {
            ForEach(chipRows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                            Button { onDelete(tag) } label: {
                                Image(systemName: "xmark")
                                    .font(.caption)
                            }
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray5))
                        .cornerRadius(14)
                    }
                }
            }
        }
    }

    /// Greedy wrap into rows of ~3 chips (kept simple; tags are short).
    private var chipRows: [[String]] {
        var rows: [[String]] = []
        var current: [String] = []
        for tag in tags {
            current.append(tag)
            if current.count == 3 {
                rows.append(current)
                current = []
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: - Add / edit form (mirrors Android MembersPage.showForm)

struct MemberFormView: View {
    let member: MemberRow?
    let allMembers: [MemberRow]
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var pin = ""
    @State private var clearPin = false
    @State private var genderIndex = 0 // 0 保密 / 1 男 / 2 女
    @State private var hasBirthday = false
    @State private var birthday = Date()
    @State private var referrerId: Int64 = -1
    @State private var note = ""
    @State private var error = ""
    @State private var showingReferrerPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.string("mem_name"), text: $name)
                    TextField(L10n.string("mem_phone"), text: $phone)
                        .keyboardType(.phonePad)
                    TextField(L10n.string("mem_email"), text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
                Section(L10n.string("mem_pin")) {
                    SecureField(member == nil
                                ? L10n.string("mem_pin_hint")
                                : L10n.string("mem_pin_hint_edit"), text: $pin)
                        .keyboardType(.numberPad)
                    if let member, !member.pinHash.isEmpty {
                        Toggle(L10n.string("mem_pin_clear"), isOn: $clearPin)
                    }
                }
                Section(L10n.string("mem_gender")) {
                    Picker(L10n.string("mem_gender"), selection: $genderIndex) {
                        Text(L10n.string("mem_gender_secret")).tag(0)
                        Text(L10n.string("mem_gender_male")).tag(1)
                        Text(L10n.string("mem_gender_female")).tag(2)
                    }
                    .pickerStyle(.segmented)
                }
                Section(L10n.string("mem_birthday")) {
                    Toggle(L10n.string("mem_birthday"), isOn: $hasBirthday)
                    if hasBirthday {
                        DatePicker(L10n.string("mem_birthday"), selection: $birthday,
                                   displayedComponents: .date)
                            .datePickerStyle(.compact)
                    }
                }
                Section(L10n.string("mem_referrer")) {
                    Button {
                        showingReferrerPicker = true
                    } label: {
                        HStack {
                            Text(referrerLabel)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                Section(L10n.string("mem_note")) {
                    TextField(L10n.string("mem_note"), text: $note)
                }
                if !error.isEmpty {
                    Text(error)
                        .foregroundColor(.red)
                }
            }
            .navigationTitle(L10n.string(member == nil ? "mem_form_title_add" : "mem_form_title_edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("mem_cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("mem_save")) { save() }
                }
            }
            .onAppear { loadInitial() }
            .sheet(isPresented: $showingReferrerPicker) {
                ReferrerPickerView(
                    candidates: allMembers.filter { $0.id != (member?.id ?? -1) },
                    selectedId: $referrerId)
            }
        }
    }

    private var referrerLabel: String {
        if referrerId > 0,
           let found = allMembers.first(where: { $0.id == referrerId }) {
            return found.name + " · " + found.phone
        }
        return L10n.string("mem_referrer_none")
    }

    private func loadInitial() {
        guard let member else { return }
        name = member.name
        phone = member.phone
        email = member.email
        genderIndex = member.gender == "男" ? 1 : member.gender == "女" ? 2 : 0
        if let date = AppDates.parseDay(member.birthday) {
            hasBirthday = true
            birthday = date
        }
        referrerId = member.referrerId
        note = member.note
    }

    private func save() {
        let db = Database.shared
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let trimmedPin = pin.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty {
            error = L10n.string("mem_err_name")
            return
        }
        if trimmedPhone.isEmpty {
            error = L10n.string("mem_err_phone")
            return
        }
        if MemberStore.phoneExists(db: db, phone: trimmedPhone,
                                   excludeId: member?.id ?? -1) {
            error = L10n.string("mem_err_phone_dup")
            return
        }
        if !trimmedEmail.isEmpty && !MemberStore.isValidEmail(trimmedEmail) {
            error = L10n.string("mem_err_email")
            return
        }
        if !trimmedPin.isEmpty && !MemberStore.isValidPin(trimmedPin) {
            error = L10n.string("mem_pin_err")
            return
        }
        var row = member ?? MemberRow(
            id: -1, name: "", phone: "", email: "", pinSalt: "", pinHash: "",
            gender: "", birthday: "", note: "", points: 0, balance: 0,
            totalSpent: 0, referrerId: -1, referralRewarded: 0, createdAt: "")
        row.name = trimmedName
        row.phone = trimmedPhone
        row.email = trimmedEmail
        row.gender = genderIndex == 1 ? "男" : genderIndex == 2 ? "女" : ""
        row.birthday = hasBirthday ? AppDates.dayString(birthday) : ""
        row.note = note.trimmingCharacters(in: .whitespaces)
        row.referrerId = referrerId
        let savedId: Int64
        if member == nil {
            savedId = MemberStore.insertMember(db: db, member: row)
            if savedId < 0 {
                error = L10n.string("db_error")
                return
            }
        } else {
            guard MemberStore.updateMember(db: db, member: row) else {
                error = L10n.string("db_error")
                return
            }
            savedId = row.id
        }
        if clearPin {
            _ = MemberStore.setMemberPin(db: db, memberId: savedId, pin: "")
        } else if !trimmedPin.isEmpty {
            _ = MemberStore.setMemberPin(db: db, memberId: savedId, pin: trimmedPin)
        }
        onSaved()
        dismiss()
    }
}

// MARK: - Referrer picker (searchable list, fix11 green + ✓ selection)

struct ReferrerPickerView: View {
    let candidates: [MemberRow]
    @Binding var selectedId: Int64

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                referrerRow(id: -1, label: L10n.string("mem_referrer_none"))
                ForEach(filtered) { member in
                    referrerRow(id: member.id,
                                label: member.name + " · " + member.phone)
                }
            }
            .searchable(text: $search, prompt: L10n.string("mem_referrer_search"))
            .navigationTitle(L10n.string("mem_referrer_pick"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common_close")) { dismiss() }
                }
            }
        }
    }

    private var filtered: [MemberRow] {
        guard !search.isEmpty else { return candidates }
        return candidates.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.phone.contains(search)
        }
    }

    private func referrerRow(id: Int64, label: String) -> some View {
        let selected = selectedId == id
        return Button {
            selectedId = id
            dismiss()
        } label: {
            HStack {
                Text(label)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .bold()
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(selected ? Brand.deepGreen : Color.clear)
            .foregroundColor(selected ? .white : Color(.label))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .listRowBackground(selected ? Brand.deepGreen.opacity(0.12) : Color.clear)
    }
}

// MARK: - Manager password gate (Android fix6 `askManagerPassword`)

/// Re-enters the current (manager) account password before a destructive
/// action. Wrong password shows an error, clears the field and stays
/// open for retry; cancel abandons the action.
struct ManagerPasswordView: View {
    let username: String
    let onVerified: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var error = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                SecureField(L10n.string("auth_pw_hint"), text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                if !error.isEmpty {
                    Text(error)
                        .foregroundColor(.red)
                }
                Button(L10n.string("common_confirm")) {
                    if Auth.verify(username: username, password: password,
                                   db: Database.shared) != nil {
                        onVerified()
                        dismiss()
                    } else {
                        error = L10n.string("auth_pw_wrong")
                        password = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.deepGreen)
                .frame(maxWidth: .infinity)
                Spacer()
            }
            .padding(16)
            .navigationTitle(L10n.string("auth_pw_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common_cancel")) { dismiss() }
                }
            }
        }
    }
}
