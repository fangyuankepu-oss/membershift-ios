import Foundation

/// Transaction engine — Swift port of Android `CheckoutEngine` (earn /
/// recharge / deduct / adjust) + `PointsLedger` (ledger batches, FIFO
/// spend, expiry) + `LedgerMath` (r2, earnFor, bonusFor).
///
/// Rules (same as Android, INVENTORY.md §3):
/// - The points balance is a cache; the points_ledger is the truth.
///   Every points change writes a ledger batch (earn) or spends FIFO.
/// - Earn: points = floor(amount × earn_rate × tier multiplier);
///   total_spent += amount; ledger source "earn"; first-purchase
///   referral reward (both sides, once).
/// - Deduct (balance payment): amount must be > 0 and ≤ balance;
///   balance -= amount; earns points like earn (source "consume");
///   tx type "checkout", pay_method "balance".
/// - Recharge: bonus = largest tier satisfied; balance += amount + bonus.
/// - Adjust: delta may be negative but points must stay ≥ 0; a positive
///   delta writes a ledger batch (source "adjust"), a negative one
///   spends FIFO.
/// - Before earn/deduct, the member's expired batches are closed
///   (points_expire tx, operator "system").
/// - All writes run in one SQLite transaction; failure rolls back.
enum PointsEngine {
    struct OpResult {
        var ok = false
        var error = ""
        var points = 0
        var bonus = 0.0
        var credited = 0.0
        var balanceAfter = 0.0
    }

    // MARK: - Settings / math

    /// Round to cents (Android `LedgerMath.r2`).
    static func r2(_ x: Double) -> Double { (x * 100).rounded() / 100 }

    /// Currency + 2 decimals, like Android `Store.money`.
    static func money(_ amount: Double, currency: String) -> String {
        String(format: "%@%.2f", currency, amount)
    }

    static func earnRate(db: Database) -> Double {
        Double(db.settingValue("earn_rate", default: "1")) ?? 1
    }

    static func referralPoints(db: Database) -> Int {
        Int(db.settingValue("referral_points", default: "50")) ?? 50
    }

    static func currency(db: Database) -> String {
        db.settingValue("currency", default: "$")
    }

    /// Earned points: floor(amount × rate × multiplier) (Android earnFor).
    static func earnFor(amount: Double, earnRate: Double, multiplier: Double) -> Int {
        Int(floor(amount * earnRate * multiplier))
    }

    /// Recharge tiers from settings JSON "[[500,50],[1000,120],[2000,300]]".
    static func rechargeTiers(db: Database) -> [(Double, Double)] {
        let json = db.settingValue("recharge_tiers", default: "[]")
        guard let data = json.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else {
            return []
        }
        var out: [(Double, Double)] = []
        for pair in raw where pair.count >= 2 {
            guard let threshold = (pair[0] as? NSNumber)?.doubleValue,
                  let bonus = (pair[1] as? NSNumber)?.doubleValue else { continue }
            out.append((threshold, bonus))
        }
        return out
    }

    /// Largest bonus whose threshold the amount reaches (Android bonusFor).
    static func bonusFor(tiers: [(Double, Double)], amount: Double) -> Double {
        var best = 0.0
        for tier in tiers where amount >= tier.0 && tier.1 > best { best = tier.1 }
        return best
    }

    /// Next tier above the amount, or nil (for the "再充到 X 可多送" hint).
    static func nextTier(tiers: [(Double, Double)], amount: Double) -> (Double, Double)? {
        tiers.filter { $0.0 > amount }.sorted { $0.0 < $1.0 }.first
    }

    /// Error code → display text (Android `CheckoutEngine.errorText`).
    static func errorText(_ error: String) -> String {
        switch error {
        case "err_need_member": return L10n.string("err_need_member")
        case "err_need_amount": return L10n.string("err_need_amount")
        case "err_balance_not_enough": return L10n.string("err_balance_not_enough")
        case "err_points_not_enough": return L10n.string("err_points_not_enough")
        default: return error
        }
    }

    // MARK: - Ledger

    @discardableResult
    static func insertTx(db: Database, type: String, memberId: Int64,
                         amount: Double, pointsChange: Int, balanceChange: Double,
                         detail: String, op: String, createdAt: String,
                         items: String = "[]", payMethod: String = "",
                         refId: Int64 = 0) -> Int64 {
        let id = db.nextId("tx")
        _ = db.execute(
            "INSERT INTO transactions (id, type, member_id, amount, points_change, balance_change, detail, operator, created_at, items, pay_method, ref_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            bindings: [.int(id), .text(type), .int(memberId), .real(r2(amount)),
                       .int(Int64(pointsChange)), .real(r2(balanceChange)), .text(detail),
                       .text(op), .text(createdAt), .text(items), .text(payMethod),
                       .int(refId)])
        return id
    }

    /// Writes an earn batch; expiry = today + points_expiry_months
    /// (0 = never expires). No-op for non-positive points.
    static func earnBatch(db: Database, memberId: Int64, pts: Int,
                          source: String, txId: Int64) {
        guard memberId > 0, pts > 0 else { return }
        let months = Int(db.settingValue("points_expiry_months", default: "12")) ?? 12
        let today = AppDates.today()
        let id = db.nextId("ledger")
        _ = db.execute(
            "INSERT INTO points_ledger (id, member_id, earn_date, expiry_date, points_total, points_used, source, tx_id) VALUES (?, ?, ?, ?, ?, 0, ?, ?)",
            bindings: [.int(id), .int(memberId), .text(today),
                       .text(AppDates.expiryDate(earnDate: today, months: months)),
                       .int(Int64(pts)), .text(source), .int(txId)])
    }

    struct LedgerBatch {
        let id: Int64
        let expiryDate: String
        let total: Int
        let used: Int
        var remaining: Int { total - used }
    }

    static func openBatches(db: Database, memberId: Int64) -> [LedgerBatch] {
        db.query(
            "SELECT id, expiry_date, points_total, points_used FROM points_ledger WHERE member_id = ? AND points_used < points_total ORDER BY id ASC",
            bindings: [.int(memberId)])
            .map {
                LedgerBatch(id: $0.int("id"), expiryDate: $0.text("expiry_date"),
                            total: Int($0.int("points_total")),
                            used: Int($0.int("points_used")))
            }
    }

    /// FIFO plan: skip expired batches; expiry ascending, never-expire
    /// last, id ascending within the same expiry (Android planSpend).
    static func planSpend(batches: [LedgerBatch], today: String, pts: Int) -> [(Int64, Int)] {
        let open = batches.filter {
            $0.remaining > 0 && ($0.expiryDate.isEmpty || $0.expiryDate >= today)
        }
        let sorted = open.sorted { a, b in
            let aNever = a.expiryDate.isEmpty
            let bNever = b.expiryDate.isEmpty
            if aNever != bNever { return bNever }
            if !aNever && a.expiryDate != b.expiryDate {
                return a.expiryDate < b.expiryDate
            }
            return a.id < b.id
        }
        var remaining = pts
        var plan: [(Int64, Int)] = []
        for batch in sorted where remaining > 0 {
            let take = min(batch.remaining, remaining)
            plan.append((batch.id, take))
            remaining -= take
        }
        return plan
    }

    /// Spends points FIFO (caller must be in a transaction).
    static func spendFifo(db: Database, memberId: Int64, pts: Int) {
        guard memberId > 0, pts > 0 else { return }
        let today = AppDates.today()
        let plan = planSpend(batches: openBatches(db: db, memberId: memberId),
                             today: today, pts: pts)
        for (id, take) in plan {
            _ = db.execute(
                "UPDATE points_ledger SET points_used = points_used + ? WHERE id = ?",
                bindings: [.int(Int64(take)), .int(id)])
        }
    }

    /// Closes the member's expired batches (caller must be in a
    /// transaction). Returns the expired point count.
    @discardableResult
    static func expireMemberPoints(db: Database, memberId: Int64) -> Int {
        let today = AppDates.today()
        let rows = db.query(
            "SELECT id, points_total, points_used FROM points_ledger WHERE member_id = ? AND expiry_date <> '' AND expiry_date < ? AND (points_total - points_used) > 0",
            bindings: [.int(memberId), .text(today)])
        var closed: [(Int64, Int)] = []
        var expired = 0
        for row in rows {
            let left = Int(row.int("points_total") - row.int("points_used"))
            guard left > 0 else { continue }
            expired += left
            closed.append((row.int("id"), left))
        }
        guard expired > 0 else { return 0 }
        for (id, _) in closed {
            _ = db.execute(
                "UPDATE points_ledger SET points_used = points_total WHERE id = ?",
                bindings: [.int(id)])
        }
        _ = db.execute("UPDATE members SET points = MAX(0, points - ?) WHERE id = ?",
                       bindings: [.int(Int64(expired)), .int(memberId)])
        let detail = String(format: L10n.string("tx_points_expire_detail"), expired)
        let txId = insertTx(db: db, type: "points_expire", memberId: memberId, amount: 0,
                            pointsChange: -expired, balanceChange: 0, detail: detail,
                            op: "system", createdAt: AppDates.now())
        for (_, left) in closed {
            let id = db.nextId("ledger")
            _ = db.execute(
                "INSERT INTO points_ledger (id, member_id, earn_date, expiry_date, points_total, points_used, source, tx_id) VALUES (?, ?, ?, ?, ?, ?, 'expiry', ?)",
                bindings: [.int(id), .int(memberId), .text(today), .text(today),
                           .int(Int64(left)), .int(Int64(left)), .int(txId)])
        }
        return expired
    }

    // MARK: - Referral

    /// First-purchase referral reward (both sides, once). Must be called
    /// after the current tx is inserted: the count must be exactly 1.
    /// `countEarnToo` mirrors Android: earn counts checkout+earn, deduct
    /// counts checkout only.
    static func grantReferralIfFirst(db: Database, memberId: Int64,
                                     op: String, countEarnToo: Bool) {
        guard let member = MemberStore.memberById(db: db, id: memberId),
              member.referrerId > 0, member.referralRewarded == 0 else { return }
        let refPts = referralPoints(db: db)
        guard refPts > 0 else { return }
        let typeFilter = countEarnToo
            ? "member_id = ? AND type IN ('checkout','earn')"
            : "member_id = ? AND type = 'checkout'"
        let count = db.query(
            "SELECT COUNT(*) AS c FROM transactions WHERE \(typeFilter)",
            bindings: [.int(memberId)]).first?.int("c") ?? 0
        guard count == 1 else { return }
        guard let referrer = MemberStore.memberById(db: db, id: member.referrerId) else { return }
        _ = db.execute(
            "UPDATE members SET referral_rewarded = 1, points = points + ? WHERE id = ?",
            bindings: [.int(Int64(refPts)), .int(memberId)])
        _ = db.execute("UPDATE members SET points = points + ? WHERE id = ?",
                       bindings: [.int(Int64(refPts)), .int(referrer.id)])
        let detail = String(format: L10n.string("tx_referral_detail"), refPts)
        let now = AppDates.now()
        let t1 = insertTx(db: db, type: "referral", memberId: memberId, amount: 0,
                          pointsChange: refPts, balanceChange: 0, detail: detail,
                          op: op, createdAt: now)
        let t2 = insertTx(db: db, type: "referral", memberId: referrer.id, amount: 0,
                          pointsChange: refPts, balanceChange: 0, detail: detail,
                          op: op, createdAt: now)
        earnBatch(db: db, memberId: memberId, pts: refPts, source: "referral", txId: t1)
        earnBatch(db: db, memberId: referrer.id, pts: refPts, source: "referral", txId: t2)
    }

    // MARK: - Operations (each one SQLite transaction)

    /// 消费兑换积分 (Android `CheckoutEngine.earn`).
    static func earn(db: Database, memberId: Int64, amount: Double, op: String) -> OpResult {
        guard MemberStore.memberById(db: db, id: memberId) != nil else {
            return OpResult(ok: false, error: "err_need_member")
        }
        guard amount > 0 else { return OpResult(ok: false, error: "err_need_amount") }
        guard db.execute("BEGIN TRANSACTION") else {
            return OpResult(ok: false, error: "err_need_amount")
        }
        var result = OpResult()
        defer { _ = db.execute(result.ok ? "COMMIT" : "ROLLBACK") }
        _ = expireMemberPoints(db: db, memberId: memberId)
        guard let m = MemberStore.memberById(db: db, id: memberId) else { return result }
        let tiers = MemberStore.loadTiers(db: db)
        let multiplier = MemberStore.tierForSpent(tiers: tiers, spent: m.totalSpent)?.multiplier ?? 1
        let pts = earnFor(amount: amount, earnRate: earnRate(db: db), multiplier: multiplier)
        let cur = currency(db: db)
        guard db.execute("UPDATE members SET points = ?, total_spent = ? WHERE id = ?",
                         bindings: [.int(m.points + Int64(pts)),
                                    .real(r2(m.totalSpent + amount)), .int(memberId)]) else {
            return result
        }
        let detail = String(format: L10n.string("tx_earn_detail"), cur,
                            String(format: "%.2f", amount))
            + " · +" + String(pts) + " " + L10n.string("tx_pts_unit")
        let txId = insertTx(db: db, type: "earn", memberId: memberId, amount: amount,
                            pointsChange: pts, balanceChange: 0, detail: detail,
                            op: op, createdAt: AppDates.now())
        if pts > 0 {
            earnBatch(db: db, memberId: memberId, pts: pts, source: "earn", txId: txId)
        }
        grantReferralIfFirst(db: db, memberId: memberId, op: op, countEarnToo: true)
        result.ok = true
        result.points = pts
        return result
    }

    /// 储值扣减 (Android `CheckoutEngine.deductBalance`).
    static func deductBalance(db: Database, memberId: Int64, amount: Double,
                              op: String) -> OpResult {
        guard MemberStore.memberById(db: db, id: memberId) != nil else {
            return OpResult(ok: false, error: "err_need_member")
        }
        guard amount > 0 else { return OpResult(ok: false, error: "err_need_amount") }
        guard db.execute("BEGIN TRANSACTION") else {
            return OpResult(ok: false, error: "err_need_amount")
        }
        var result = OpResult()
        defer { _ = db.execute(result.ok ? "COMMIT" : "ROLLBACK") }
        _ = expireMemberPoints(db: db, memberId: memberId)
        guard let m = MemberStore.memberById(db: db, id: memberId) else { return result }
        guard m.balance + 1e-9 >= amount else {
            result.error = "err_balance_not_enough"
            return result
        }
        let tiers = MemberStore.loadTiers(db: db)
        let multiplier = MemberStore.tierForSpent(tiers: tiers, spent: m.totalSpent)?.multiplier ?? 1
        let pts = earnFor(amount: amount, earnRate: earnRate(db: db), multiplier: multiplier)
        let newBalance = r2(m.balance - amount)
        let cur = currency(db: db)
        guard db.execute("UPDATE members SET points = ?, balance = ?, total_spent = ? WHERE id = ?",
                         bindings: [.int(m.points + Int64(pts)), .real(newBalance),
                                    .real(r2(m.totalSpent + amount)), .int(memberId)]) else {
            return result
        }
        let detail = String(format: L10n.string("tx_deduct_detail"), cur,
                            String(format: "%.2f", amount), pts)
        let txId = insertTx(db: db, type: "checkout", memberId: memberId, amount: amount,
                            pointsChange: pts, balanceChange: -amount, detail: detail,
                            op: op, createdAt: AppDates.now(), payMethod: "balance")
        if pts > 0 {
            earnBatch(db: db, memberId: memberId, pts: pts, source: "consume", txId: txId)
        }
        grantReferralIfFirst(db: db, memberId: memberId, op: op, countEarnToo: false)
        result.ok = true
        result.points = pts
        result.balanceAfter = newBalance
        return result
    }

    /// 储值充值 (Android `CheckoutEngine.recharge`).
    static func recharge(db: Database, memberId: Int64, amount: Double,
                         op: String) -> OpResult {
        guard MemberStore.memberById(db: db, id: memberId) != nil else {
            return OpResult(ok: false, error: "err_need_member")
        }
        guard amount > 0 else { return OpResult(ok: false, error: "err_need_amount") }
        let bonus = bonusFor(tiers: rechargeTiers(db: db), amount: amount)
        let credited = r2(amount + bonus)
        guard db.execute("BEGIN TRANSACTION") else {
            return OpResult(ok: false, error: "err_need_amount")
        }
        var result = OpResult()
        defer { _ = db.execute(result.ok ? "COMMIT" : "ROLLBACK") }
        guard let m = MemberStore.memberById(db: db, id: memberId) else { return result }
        guard db.execute("UPDATE members SET balance = ? WHERE id = ?",
                         bindings: [.real(r2(m.balance + credited)), .int(memberId)]) else {
            return result
        }
        let cur = currency(db: db)
        let detail = String(format: L10n.string("tx_recharge_detail"), cur,
                            String(format: "%.2f", amount), cur,
                            String(format: "%.2f", bonus))
        _ = insertTx(db: db, type: "recharge", memberId: memberId, amount: amount,
                     pointsChange: 0, balanceChange: credited, detail: detail,
                     op: op, createdAt: AppDates.now())
        result.ok = true
        result.bonus = bonus
        result.credited = credited
        return result
    }

    /// 手动调整积分 (Android `CheckoutEngine.adjust`; manager only — the
    /// caller enforces the permission).
    static func adjust(db: Database, memberId: Int64, delta: Int,
                       reason: String, op: String) -> OpResult {
        guard let m = MemberStore.memberById(db: db, id: memberId) else {
            return OpResult(ok: false, error: "err_need_member")
        }
        guard delta != 0 else { return OpResult(ok: false, error: "err_need_amount") }
        guard m.points + Int64(delta) >= 0 else {
            return OpResult(ok: false, error: "err_points_not_enough")
        }
        guard db.execute("BEGIN TRANSACTION") else {
            return OpResult(ok: false, error: "err_need_amount")
        }
        var result = OpResult()
        defer { _ = db.execute(result.ok ? "COMMIT" : "ROLLBACK") }
        guard db.execute("UPDATE members SET points = ? WHERE id = ?",
                         bindings: [.int(m.points + Int64(delta)), .int(memberId)]) else {
            return result
        }
        let detail = L10n.string("tx_adjust_detail")
            + (reason.trimmingCharacters(in: .whitespaces).isEmpty
                ? "" : "：" + reason.trimmingCharacters(in: .whitespaces))
        let txId = insertTx(db: db, type: "adjust", memberId: memberId, amount: 0,
                            pointsChange: delta, balanceChange: 0, detail: detail,
                            op: op, createdAt: AppDates.now())
        if delta > 0 {
            earnBatch(db: db, memberId: memberId, pts: delta, source: "adjust", txId: txId)
        } else {
            spendFifo(db: db, memberId: memberId, pts: -delta)
        }
        result.ok = true
        result.points = delta
        return result
    }
}
