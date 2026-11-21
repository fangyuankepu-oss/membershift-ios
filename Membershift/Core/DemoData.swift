import Foundation

/// Demo-data loader — 1:1 port of Android `DemoData.load`.
///
/// - 3 members: 王小明 / 13800000001 (男), 李小红 / 13800000002 (女),
///   张大强 / 13800000003 (男).
/// - One demo checkout each: 王小明 ¥268 cash today (+268 pts),
///   李小红 ¥156 WeChat yesterday (+156 pts), 张大强 ¥320 Alipay
///   3 days ago (+320 pts).
/// - 李小红 also gets a ¥500 stored-value recharge (+¥50 bonus, +550
///   balance) and a 120-point ledger batch expiring within 30 days.
/// - 李小红's referrer is 王小明 (reward is only granted on first
///   purchase by the checkout logic, not by the loader).
/// - Loading is skipped (returns false) if any of the three phones
///   already exists, so a second load never duplicates data.
/// - Everything runs in one SQLite transaction; points are written to
///   the points_ledger at the same time (the ledger is the truth).
///
/// The Dashboard auto-loads this on first appearance when the members
/// and transactions tables are empty, so a fresh install shows real
/// numbers immediately instead of an empty page.
enum DemoData {
    static let members: [(name: String, phone: String, gender: String)] = [
        ("王小明", "13800000001", "男"),
        ("李小红", "13800000002", "女"),
        ("张大强", "13800000003", "男"),
    ]

    @discardableResult
    static func loadIfNeeded(db: Database) -> Bool {
        if phoneExists(db, "13800000001")
            || phoneExists(db, "13800000002")
            || phoneExists(db, "13800000003") {
            return false
        }
        let today = AppDates.today()
        let yesterday = AppDates.addDays(today, -1)
        let threeDaysAgo = AppDates.addDays(today, -3)

        guard db.execute("BEGIN TRANSACTION") else { return false }
        var ok = true

        // 王小明：生日在 3 天后（进“未来 7 天生日”），5 天前入会。
        let id1 = insertMember(db, name: "王小明", phone: "13800000001", gender: "男",
                               birthday: AppDates.addDays(today, 3),
                               createdDay: AppDates.addDays(today, -5))
        ok = ok && id1 > 0
        // 李小红：10 天前入会。
        let id2 = insertMember(db, name: "李小红", phone: "13800000002", gender: "女",
                               birthday: "1992-06-15",
                               createdDay: AppDates.addDays(today, -10))
        ok = ok && id2 > 0
        // 张大强：20 天前入会。
        let id3 = insertMember(db, name: "张大强", phone: "13800000003", gender: "男",
                               birthday: "1988-11-20",
                               createdDay: AppDates.addDays(today, -20))
        ok = ok && id3 > 0

        // 王小明：今日结算 268（现金），赚 268 分。
        if ok {
            ok = insertTx(db, type: "checkout", memberId: id1, amount: 268, pointsChange: 268,
                          balanceChange: 0, detail: "消费结算", op: "admin",
                          createdAt: today + " 14:30:00", payMethod: "现金",
                          items: itemsJSON([
                            (name: "招牌鸭脖", price: 88, qty: 2, category: "卤味"),
                            (name: "鸭翅", price: 46, qty: 2, category: "卤味"),
                          ])) > 0
            addLedger(db, memberId: id1, earnDate: today, points: 268, source: "earn")
            ok = ok && updateMemberTotals(db, memberId: id1, spent: 268, points: 268, balance: 0)
        }

        // 李小红：昨日结算 156（微信），赚 156 分；另有一批 120 分 30 天内到期。
        if ok {
            ok = insertTx(db, type: "checkout", memberId: id2, amount: 156, pointsChange: 156,
                          balanceChange: 0, detail: "消费结算", op: "admin",
                          createdAt: yesterday + " 11:20:00", payMethod: "微信",
                          items: itemsJSON([
                            (name: "鸭脖", price: 78, qty: 2, category: "卤味"),
                          ])) > 0
            addLedger(db, memberId: id2, earnDate: yesterday, points: 156, source: "earn")
            // 11 个月前入账的 120 分：12 个月有效期 → 1 个月后到期（30 天内）。
            addLedger(db, memberId: id2, earnDate: AppDates.addMonths(today, -11),
                      points: 120, source: "demo")
            ok = ok && updateMemberTotals(db, memberId: id2, spent: 156, points: 156 + 120, balance: 0)
            // 李小红推荐人是王小明（待首单发放由结算逻辑触发，这里只建关系）。
            ok = ok && db.execute("UPDATE members SET referrer_id = ? WHERE id = ?",
                                   bindings: [.int(id1), .int(id2)])
        }

        // 李小红：今日储值充值 500，赠送 50，到账 550。
        if ok {
            ok = insertTx(db, type: "recharge", memberId: id2, amount: 500, pointsChange: 0,
                          balanceChange: 550, detail: "储值充值 500，赠送 50", op: "admin",
                          createdAt: today + " 10:05:00", payMethod: "", items: "[]") > 0
            ok = ok && updateMemberTotals(db, memberId: id2, spent: 0, points: 0, balance: 550)
        }

        // 张大强：3 天前结算 320（支付宝），赚 320 分。
        if ok {
            ok = insertTx(db, type: "checkout", memberId: id3, amount: 320, pointsChange: 320,
                          balanceChange: 0, detail: "消费结算", op: "admin",
                          createdAt: threeDaysAgo + " 18:45:00", payMethod: "支付宝",
                          items: itemsJSON([
                            (name: "全套餐", price: 160, qty: 2, category: "套餐"),
                          ])) > 0
            addLedger(db, memberId: id3, earnDate: threeDaysAgo, points: 320, source: "earn")
            ok = ok && updateMemberTotals(db, memberId: id3, spent: 320, points: 320, balance: 0)
        }

        if ok {
            ok = db.execute("COMMIT")
        } else {
            db.execute("ROLLBACK")
        }
        return ok
    }

    private static func phoneExists(_ db: Database, _ phone: String) -> Bool {
        let rows = db.query("SELECT COUNT(*) AS c FROM members WHERE phone = ?",
                            bindings: [.text(phone)])
        return (rows.first?.int("c") ?? 0) > 0
    }

    private static func insertMember(_ db: Database, name: String, phone: String,
                                     gender: String, birthday: String,
                                     createdDay: String) -> Int64 {
        let id = db.nextId("member")
        let ok = db.execute(
            "INSERT INTO members (id, name, phone, gender, birthday, note, points, balance, total_spent, referrer_id, referral_rewarded, created_at) VALUES (?, ?, ?, ?, ?, '', 0, 0, 0, NULL, 0, ?)",
            bindings: [.int(id), .text(name), .text(phone), .text(gender), .text(birthday),
                       .text(createdDay + " 09:00:00")])
        return ok ? id : -1
    }

    private static func itemsJSON(_ rows: [(name: String, price: Double, qty: Int, category: String)]) -> String {
        let array: [[String: Any]] = rows.map { row in
            ["name": row.name, "price": row.price, "qty": row.qty, "category": row.category]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: array),
              let string = String(data: data, encoding: .utf8) else { return "[]" }
        return string
    }

    private static func insertTx(_ db: Database, type: String, memberId: Int64,
                                 amount: Double, pointsChange: Int64, balanceChange: Double,
                                 detail: String, op: String, createdAt: String,
                                 payMethod: String, items: String) -> Int64 {
        let id = db.nextId("tx")
        let ok = db.execute(
            "INSERT INTO transactions (id, type, member_id, amount, points_change, balance_change, detail, operator, created_at, items, pay_method, ref_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)",
            bindings: [.int(id), .text(type), .int(memberId), .real(amount), .int(pointsChange),
                       .real(balanceChange), .text(detail), .text(op), .text(createdAt),
                       .text(items), .text(payMethod)])
        return ok ? id : -1
    }

    /// Writes a points batch to the ledger; expiry follows
    /// settings.points_expiry_months (default 12).
    private static func addLedger(_ db: Database, memberId: Int64, earnDate: String,
                                  points: Int64, source: String) {
        let months = Int(db.settingValue("points_expiry_months", default: "12")) ?? 12
        let id = db.nextId("ledger")
        db.execute(
            "INSERT INTO points_ledger (id, member_id, earn_date, expiry_date, points_total, points_used, source, tx_id) VALUES (?, ?, ?, ?, ?, 0, ?, -1)",
            bindings: [.int(id), .int(memberId), .text(earnDate),
                       .text(AppDates.expiryDate(earnDate: earnDate, months: months)),
                       .int(points), .text(source)])
    }

    /// Increments a member's total spent / points / balance.
    private static func updateMemberTotals(_ db: Database, memberId: Int64,
                                           spent: Double, points: Int64,
                                           balance: Double) -> Bool {
        db.execute(
            "UPDATE members SET total_spent = total_spent + ?, points = points + ?, balance = balance + ? WHERE id = ?",
            bindings: [.real(spent), .int(points), .real(balance), .int(memberId)])
    }
}
