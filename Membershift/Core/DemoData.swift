import Foundation

/// Demo-data loader — STUB for phase 1.
///
/// Android behaviour to port in phase 2 (`DemoData.load`):
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
///   already exists, so a second tap never duplicates data.
enum DemoData {
    static let members: [(name: String, phone: String, gender: String)] = [
        ("王小明", "13800000001", "男"),
        ("李小红", "13800000002", "女"),
        ("张大强", "13800000003", "男"),
    ]

    @discardableResult
    static func loadIfNeeded(db: Database) -> Bool {
        // TODO (phase 2): port Android DemoData.load as described above.
        false
    }
}
