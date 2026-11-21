import Foundation

/// Date helpers. The DB stores datetimes as "yyyy-MM-dd HH:mm:ss" and
/// dates as "yyyy-MM-dd" (same as Android `DateUtils`); lexicographic
/// comparison is chronological order, and SQLite `date()` parses them.
///
/// Month arithmetic clamps at month-end (Jan 31 + 1 month = Feb 28),
/// matching Android `Calendar.add(MONTH, ...)`.
enum AppDates {
    static let dayFormat = "yyyy-MM-dd"
    static let dateTimeFormat = "yyyy-MM-dd HH:mm:ss"

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    static func today() -> String {
        formatter(dayFormat).string(from: Date())
    }

    static func now() -> String {
        formatter(dateTimeFormat).string(from: Date())
    }

    static func parseDay(_ day: String) -> Date? {
        formatter(dayFormat).date(from: day)
    }

    /// `day` (yyyy-MM-dd) plus `n` days.
    static func addDays(_ day: String, _ n: Int) -> String {
        guard let date = parseDay(day) else { return today() }
        let shifted = Calendar.current.date(byAdding: .day, value: n, to: date) ?? date
        return formatter(dayFormat).string(from: shifted)
    }

    /// `day` (yyyy-MM-dd) plus `n` months (month-end clamps).
    static func addMonths(_ day: String, _ n: Int) -> String {
        guard let date = parseDay(day) else { return today() }
        let shifted = Calendar.current.date(byAdding: .month, value: n, to: date) ?? date
        return formatter(dayFormat).string(from: shifted)
    }

    /// First day of the current month.
    static func monthStart() -> String {
        let parts = Calendar.current.dateComponents([.year, .month], from: Date())
        let first = Calendar.current.date(from: parts) ?? Date()
        return formatter(dayFormat).string(from: first)
    }

    /// Monday of the current week (Monday is the week start),
    /// like Android `DateUtils.weekStart`.
    static func weekStart() -> String {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        // Calendar weekday: 1 = Sunday … 7 = Saturday.
        // Monday start: Sunday goes back 6 days, other days back (weekday - 2).
        let delta = weekday == 1 ? -6 : -(weekday - 2)
        let monday = calendar.date(byAdding: .day, value: delta, to: Date()) ?? Date()
        return formatter(dayFormat).string(from: monday)
    }

    /// "yyyy-MM-dd" for a Date.
    static func dayString(_ date: Date) -> String {
        formatter(dayFormat).string(from: date)
    }

    /// Days between two "yyyy-MM-dd" dates (b - a), like Android
    /// `DateUtils.daysBetween`.
    static func daysBetween(_ a: String, _ b: String) -> Int {
        guard let da = parseDay(a), let db = parseDay(b) else { return 0 }
        return Int(db.timeIntervalSince(da) / 86400)
    }

    /// Every day in the closed range [start, end], like Android
    /// `DateUtils.daysInRange` (truncated at 370 days).
    static func daysInRange(_ start: String, _ end: String) -> [String] {
        guard let ds = parseDay(start), let de = parseDay(end), ds <= de else { return [] }
        var out: [String] = []
        var current = ds
        var guardCount = 0
        while current <= de && guardCount < 370 {
            out.append(formatter(dayFormat).string(from: current))
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
            guardCount += 1
        }
        return out
    }

    /// The previous equal-length range, like Android
    /// `DateUtils.prevRange`: [start - len, end - len].
    static func prevRange(_ start: String, _ end: String) -> (String, String) {
        let len = daysBetween(start, end) + 1
        return (addDays(start, -len), addDays(end, -len))
    }

    /// Earn date + `months` validity; `months <= 0` means never expires.
    static func expiryDate(earnDate: String, months: Int) -> String {
        guard months > 0 else { return "" }
        return addMonths(earnDate, months)
    }

    /// "MM-dd" part of a "yyyy-MM-dd" birthday.
    static func birthdayMd(_ birthday: String) -> String {
        guard birthday.count >= 10 else { return "" }
        return String(birthday.dropFirst(5).prefix(5))
    }

    /// Whether the birthday's month-day falls within the next `days` days
    /// (today included, year wrap handled), like Android
    /// `DateUtils.birthdayWithin`.
    static func birthdayWithin(_ birthday: String, days: Int) -> Bool {
        (daysUntilBirthday(birthday) ?? Int.max) <= days
    }

    /// Days from today until the next occurrence of the birthday's
    /// month-day (0 = today), or nil for a missing/invalid birthday.
    static func daysUntilBirthday(_ birthday: String) -> Int? {
        guard birthday.count >= 10 else { return nil }
        let md = birthdayMd(birthday)
        let mdFormat = formatter("MM-dd")
        for i in 0...366 {
            let date = Calendar.current.date(byAdding: .day, value: i, to: Date()) ?? Date()
            if mdFormat.string(from: date) == md { return i }
        }
        return nil
    }
}
