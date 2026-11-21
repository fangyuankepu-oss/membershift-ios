import Foundation
import SQLite3

/// Values that can be bound to a `?` placeholder.
enum SQLiteValue {
    case null
    case int(Int64)
    case real(Double)
    case text(String)
}

/// sqlite3 destructor constant meaning "SQLite makes its own copy".
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// One result row: column names plus typed values. Accessors coerce
/// between types so callers don't have to care whether SQLite stored a
/// number as INTEGER, REAL or TEXT.
struct DBRow {
    let columns: [String]
    private let values: [SQLiteValue]

    init(columns: [String], values: [SQLiteValue]) {
        self.columns = columns
        self.values = values
    }

    func text(_ name: String) -> String {
        guard let index = columns.firstIndex(of: name) else { return "" }
        switch values[index] {
        case .text(let value): return value
        case .int(let value): return String(value)
        case .real(let value): return String(value)
        case .null: return ""
        }
    }

    func int(_ name: String) -> Int64 {
        guard let index = columns.firstIndex(of: name) else { return 0 }
        switch values[index] {
        case .int(let value): return value
        case .real(let value): return Int64(value)
        case .text(let value): return Int64(value) ?? 0
        case .null: return 0
        }
    }

    func real(_ name: String) -> Double {
        guard let index = columns.firstIndex(of: name) else { return 0 }
        switch values[index] {
        case .real(let value): return value
        case .int(let value): return Double(value)
        case .text(let value): return Double(value) ?? 0
        case .null: return 0
        }
    }
}

/// Thin wrapper over the system libsqlite3 (no third-party dependency).
///
/// Schema is a 1:1 port of Android `DbHelper` (DB_VERSION 4): 14 tables,
/// same names / columns / types / defaults, same seed data, same file name
/// (`member_system.db`). Android note: FINAL.md says "12 tables" but
/// DbHelper actually creates 14 (10 collections + bookings + settings +
/// license + seq); all 14 are ported here.
final class Database {
    static let shared = Database()

    private var handle: OpaquePointer?
    private(set) var isOpen = false
    private(set) var openError: String?

    static let fileName = "member_system.db"

    var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask).first!
        return dir.appendingPathComponent(Self.fileName)
    }

    private init() {}

    // MARK: - Open / schema / seed

    /// Opens (creating if needed) the database, creates the schema if
    /// missing, and seeds defaults only when the users table is empty,
    /// so re-opens and upgrades are safe.
    @discardableResult
    func open() -> Bool {
        guard !isOpen else { return true }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: fileURL.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
        } catch {
            openError = "Cannot create data directory: \(error.localizedDescription)"
            return false
        }
        let rc = fileURL.path.withCString { cPath in
            sqlite3_open(cPath, &handle)
        }
        guard rc == SQLITE_OK, handle != nil else {
            openError = "sqlite3_open failed: \(lastErrorMessage)"
            return false
        }
        guard createSchema(), seedIfNeeded() else { return false }
        isOpen = true
        return true
    }

    private var lastErrorMessage: String {
        guard let h = handle, let c = sqlite3_errmsg(h) else { return "unknown error" }
        return String(cString: c)
    }

    /// CREATE TABLE statements ported verbatim from Android DbHelper
    /// (onCreate, DB_VERSION 4), with `IF NOT EXISTS` added so the call
    /// is idempotent.
    private static let schemaSQL: [String] = [
        """
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY, username TEXT UNIQUE NOT NULL,
            salt TEXT, pw_hash TEXT, role TEXT DEFAULT 'staff', perms TEXT DEFAULT '[]')
        """,
        """
        CREATE TABLE IF NOT EXISTS tiers (
            id INTEGER PRIMARY KEY, name TEXT, min_spent REAL DEFAULT 0,
            discount REAL DEFAULT 1, multiplier REAL DEFAULT 1, color TEXT)
        """,
        """
        CREATE TABLE IF NOT EXISTS members (
            id INTEGER PRIMARY KEY, name TEXT, phone TEXT UNIQUE, email TEXT DEFAULT '',
            pin_salt TEXT DEFAULT '', pin_hash TEXT DEFAULT '',
            gender TEXT DEFAULT '',
            birthday TEXT, note TEXT DEFAULT '', points INTEGER DEFAULT 0,
            balance REAL DEFAULT 0, total_spent REAL DEFAULT 0,
            referrer_id INTEGER, referral_rewarded INTEGER DEFAULT 0, created_at TEXT)
        """,
        """
        CREATE TABLE IF NOT EXISTS gifts (
            id INTEGER PRIMARY KEY, name TEXT, icon TEXT DEFAULT '🎁',
            points INTEGER DEFAULT 0, stock INTEGER DEFAULT 0)
        """,
        """
        CREATE TABLE IF NOT EXISTS coupons (
            id INTEGER PRIMARY KEY, name TEXT, type TEXT DEFAULT 'amount',
            min_spend REAL DEFAULT 0, off REAL DEFAULT 0, percent REAL DEFAULT 0,
            valid_days INTEGER DEFAULT 0, categories TEXT DEFAULT '[]',
            product_ids TEXT DEFAULT '[]', per_member_limit INTEGER DEFAULT 0,
            total_limit INTEGER DEFAULT 0, start_date TEXT, end_date TEXT,
            stackable INTEGER DEFAULT 1)
        """,
        """
        CREATE TABLE IF NOT EXISTS member_coupons (
            id INTEGER PRIMARY KEY, member_id INTEGER, coupon_id INTEGER,
            status TEXT DEFAULT 'unused', issued_at TEXT, expires_at TEXT, used_at TEXT)
        """,
        """
        CREATE TABLE IF NOT EXISTS transactions (
            id INTEGER PRIMARY KEY, type TEXT, member_id INTEGER, amount REAL DEFAULT 0,
            points_change INTEGER DEFAULT 0, balance_change REAL DEFAULT 0,
            detail TEXT DEFAULT '', operator TEXT DEFAULT '', created_at TEXT,
            items TEXT DEFAULT '[]', pay_method TEXT DEFAULT '', ref_id INTEGER DEFAULT 0)
        """,
        """
        CREATE TABLE IF NOT EXISTS products (
            id INTEGER PRIMARY KEY, name TEXT, name_en TEXT DEFAULT '', price REAL DEFAULT 0,
            category TEXT DEFAULT '', stock INTEGER DEFAULT 0, note TEXT DEFAULT '',
            active INTEGER DEFAULT 1)
        """,
        """
        CREATE TABLE IF NOT EXISTS points_ledger (
            id INTEGER PRIMARY KEY, member_id INTEGER, earn_date TEXT,
            expiry_date TEXT DEFAULT '', points_total INTEGER DEFAULT 0,
            points_used INTEGER DEFAULT 0, source TEXT, tx_id INTEGER)
        """,
        """
        CREATE TABLE IF NOT EXISTS member_tags (
            member_id INTEGER, tag TEXT, PRIMARY KEY(member_id, tag))
        """,
        """
        CREATE TABLE IF NOT EXISTS bookings (
            id INTEGER PRIMARY KEY, member_id INTEGER, staff TEXT DEFAULT '',
            service TEXT DEFAULT '', start_time TEXT, end_time TEXT,
            status TEXT DEFAULT '待确认', note TEXT DEFAULT '', created_at TEXT)
        """,
        "CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)",
        "CREATE TABLE IF NOT EXISTS license (key TEXT PRIMARY KEY, value TEXT)",
        "CREATE TABLE IF NOT EXISTS seq (name TEXT PRIMARY KEY, next_id INTEGER DEFAULT 1)",
    ]

    private func createSchema() -> Bool {
        for sql in Self.schemaSQL {
            guard execute(sql) else { return false }
        }
        return true
    }

    /// Fresh-install defaults, ported from Android DbHelper.seedDefaults.
    /// Aligned values (same as Android native / desktop / poster rules):
    /// redeem_rate=20 (20 pts = $1), referral_points=50 per side,
    /// min_redeem_points=100, points_expiry_months=12, trial 14 days.
    private func seedIfNeeded() -> Bool {
        let count = scalarInt("SELECT COUNT(*) FROM users") ?? -1
        guard count == 0 else { return count >= 0 }
        guard execute("BEGIN TRANSACTION") else { return false }
        var ok = true

        let salt = Auth.makeSalt()
        ok = ok && execute(
            "INSERT INTO users (id, username, salt, pw_hash, role, perms) VALUES (1, 'admin', ?, ?, 'manager', '[]')",
            bindings: [.text(salt), .text(Auth.hashPassword("123456", salt: salt))])

        let tiers: [(Int64, String, Double, Double, Double, String)] = [
            (1, "普通会员", 0, 1.0, 1.0, "#94a3b8"),
            (2, "银卡会员", 5000, 0.95, 1.5, "#64748b"),
            (3, "金卡会员", 20000, 0.9, 2.0, "#d97706"),
            (4, "钻石会员", 50000, 0.85, 3.0, "#7c3aed"),
        ]
        for t in tiers {
            ok = ok && execute(
                "INSERT INTO tiers (id, name, min_spent, discount, multiplier, color) VALUES (?, ?, ?, ?, ?, ?)",
                bindings: [.int(t.0), .text(t.1), .real(t.2), .real(t.3), .real(t.4), .text(t.5)])
        }

        let gifts: [(Int64, String, String, Int64, Int64)] = [
            (1, "精美水杯", "🥤", 500, 20),
            (2, "雨伞", "☂️", 800, 15),
            (3, "50元代金券", "🎫", 2000, 50),
        ]
        for g in gifts {
            ok = ok && execute(
                "INSERT INTO gifts (id, name, icon, points, stock) VALUES (?, ?, ?, ?, ?)",
                bindings: [.int(g.0), .text(g.1), .text(g.2), .int(g.3), .int(g.4)])
        }

        let settings: [(String, String)] = [
            ("shop_name", "我的店铺"),
            ("earn_rate", "1"),
            ("redeem_rate", "20"),
            ("points_expiry_months", "12"),
            ("referral_points", "50"),
            ("min_redeem_points", "100"),
            ("currency", "$"),
            ("printer_addr", ""),
            ("printer_name", ""),
            ("printer_mode", "bt"),
            ("paper", "58"),
            ("auto_print", "0"),
            ("auto_print_exchange", "1"),
            ("auto_print_adjust", "0"),
            ("migration_done", "0"),
            ("auto_backup_at", ""),
            ("receipt_tpl.header", ""),
            ("receipt_tpl.footer", ""),
            ("receipt_tpl.show_tier", "1"),
            ("receipt_tpl.show_points", "1"),
            ("receipt_tpl.show_balance", "1"),
            ("receipt_tpl.show_operator", "1"),
            ("receipt_tpl.show_time", "1"),
            ("recharge_tiers", "[[500,50],[1000,120],[2000,300]]"),
            ("hours_start", "09:00"),
            ("hours_end", "21:00"),
            ("hours_end_next_day", "0"),
        ]
        for s in settings {
            ok = ok && execute("INSERT INTO settings (key, value) VALUES (?, ?)",
                               bindings: [.text(s.0), .text(s.1)])
        }

        ok = ok && execute("INSERT INTO license (key, value) VALUES ('installed_at', ?)",
                           bindings: [.text(Self.todayString())])
        ok = ok && execute("INSERT INTO license (key, value) VALUES ('code', '')")
        ok = ok && execute("INSERT INTO license (key, value) VALUES ('expires_at', '')")

        let seq: [(String, Int64)] = [
            ("user", 2), ("tier", 5), ("member", 1), ("gift", 4), ("coupon", 1),
            ("mc", 1), ("tx", 1), ("ledger", 1), ("product", 1), ("booking", 1),
        ]
        for row in seq {
            ok = ok && execute("INSERT INTO seq (name, next_id) VALUES (?, ?)",
                               bindings: [.text(row.0), .int(row.1)])
        }

        if ok {
            ok = execute("COMMIT")
        } else {
            execute("ROLLBACK")
        }
        return ok
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    // MARK: - Statement helpers

    @discardableResult
    func execute(_ sql: String, bindings: [SQLiteValue] = []) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt else {
            openError = lastErrorMessage
            return false
        }
        defer { sqlite3_finalize(stmt) }
        for (index, value) in bindings.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .null:
                sqlite3_bind_null(stmt, position)
            case .int(let v):
                sqlite3_bind_int64(stmt, position, v)
            case .real(let v):
                sqlite3_bind_double(stmt, position, v)
            case .text(let v):
                sqlite3_bind_text(stmt, position, v, -1, SQLITE_TRANSIENT)
            }
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            openError = lastErrorMessage
            return false
        }
        return true
    }

    func scalarInt(_ sql: String) -> Int64? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(stmt, 0)
    }

    func scalarReal(_ sql: String) -> Double? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_double(stmt, 0)
    }

    /// Runs a SELECT and returns every row. Used by the phase-2 pages
    /// (Dashboard, …) for their aggregate / list queries.
    func query(_ sql: String, bindings: [SQLiteValue] = []) -> [DBRow] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }
        bindValues(stmt, bindings)
        var rows: [DBRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let count = sqlite3_column_count(stmt)
            var columns: [String] = []
            var values: [SQLiteValue] = []
            for index in 0..<count {
                if let name = sqlite3_column_name(stmt, index) {
                    columns.append(String(cString: name))
                } else {
                    columns.append("")
                }
                switch sqlite3_column_type(stmt, index) {
                case SQLITE_INTEGER:
                    values.append(.int(sqlite3_column_int64(stmt, index)))
                case SQLITE_FLOAT:
                    values.append(.real(sqlite3_column_double(stmt, index)))
                case SQLITE_NULL:
                    values.append(.null)
                default:
                    values.append(.text(columnText(stmt, index) ?? ""))
                }
            }
            rows.append(DBRow(columns: columns, values: values))
        }
        return rows
    }

    private func bindValues(_ stmt: OpaquePointer, _ bindings: [SQLiteValue]) {
        for (index, value) in bindings.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .null:
                sqlite3_bind_null(stmt, position)
            case .int(let value):
                sqlite3_bind_int64(stmt, position, value)
            case .real(let value):
                sqlite3_bind_double(stmt, position, value)
            case .text(let value):
                sqlite3_bind_text(stmt, position, value, -1, SQLITE_TRANSIENT)
            }
        }
    }

    private func keyValue(table: String, key: String, default defaultValue: String) -> String {
        var stmt: OpaquePointer?
        let sql = "SELECT value FROM \(table) WHERE key = ?"
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt else { return defaultValue }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let text = columnText(stmt, 0) else { return defaultValue }
        return text
    }

    func settingValue(_ key: String, default defaultValue: String) -> String {
        keyValue(table: "settings", key: key, default: defaultValue)
    }

    func licenseValue(_ key: String, default defaultValue: String) -> String {
        keyValue(table: "license", key: key, default: defaultValue)
    }

    func setSetting(_ key: String, value: String) -> Bool {
        execute("INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                bindings: [.text(key), .text(value)])
    }

    /// Next id for a sequence name (same contract as Android DbHelper.nextId;
    /// callers should use it inside a transaction for atomicity).
    func nextId(_ name: String) -> Int64 {
        var stmt: OpaquePointer?
        var current: Int64 = 1
        if sqlite3_prepare_v2(handle, "SELECT next_id FROM seq WHERE name = ?", -1, &stmt, nil) == SQLITE_OK,
           let stmt {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                current = sqlite3_column_int64(stmt, 0)
            }
        }
        execute("INSERT INTO seq (name, next_id) VALUES (?, ?) ON CONFLICT(name) DO UPDATE SET next_id = excluded.next_id",
                bindings: [.text(name), .int(current + 1)])
        return current
    }

    // MARK: - Auth queries

    struct UserRow {
        let id: Int64
        let salt: String
        let hash: String
        let username: String
        let role: String
        let perms: String
    }

    func queryUser(username: String) -> UserRow? {
        var stmt: OpaquePointer?
        let sql = "SELECT id, salt, pw_hash, username, role, perms FROM users WHERE username = ?"
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, username, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return UserRow(
            id: sqlite3_column_int64(stmt, 0),
            salt: columnText(stmt, 1) ?? "",
            hash: columnText(stmt, 2) ?? "",
            username: columnText(stmt, 3) ?? "",
            role: columnText(stmt, 4) ?? "staff",
            perms: columnText(stmt, 5) ?? "[]"
        )
    }

    func updateUserHash(userId: Int64, hash: String) -> Bool {
        execute("UPDATE users SET pw_hash = ? WHERE id = ?",
                bindings: [.text(hash), .int(userId)])
    }

    private func columnText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let raw = sqlite3_column_text(stmt, index) else { return nil }
        return raw.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
    }
}
