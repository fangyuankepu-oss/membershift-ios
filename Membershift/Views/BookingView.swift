import SwiftUI

/// Booking — mirrors Android `BookingPage` + `BookingStore`.
///
/// - 4 modes: 日 / 周 / 月 / 列表 (same order as Android).
/// - Day: 30-minute slot cards from business hours; tap a slot (or its
///   "＋ 点击预约") to create a booking at that slot.
/// - Week: one card per day (date chip + count/free + ＋ button).
/// - Month: calendar grid (localized weekday header) + the selected
///   day's bookings below.
/// - List: upcoming bookings from today, max 100.
/// - Booking card: time + status pill, member · staff · service, note;
///   tap for actions (confirm / complete / no-show / cancel / edit /
///   delete, status-dependent like Android).
/// - Form: member picker (walk-in allowed), staff picker (unassigned +
///   user accounts + custom), service picker (history + products +
///   categories + custom), start/end date+time pickers (changing start
///   moves end +30 min), +30 min button, note. Save validates end >
///   start, business hours, and conflicts (same staff rule as Android).
/// - Business-hours editor: card at the bottom of the page (iOS
///   Settings is still a placeholder); start/end + "closes next day".
///
/// Known Android edge kept: `listDay` includes a booking that started
/// the previous day and runs past midnight, but day-view slots only
/// match bookings whose start_time equals the slot — such a booking
/// does not attach to any slot row (it still shows in week/month/list).
struct BookingRow: Identifiable {
    let id: Int64
    var memberId: Int64 // -1 = walk-in (member_id NULL)
    var staff: String // "" = unassigned
    var service: String
    var startTime: String // "yyyy-MM-dd HH:mm"
    var endTime: String
    var status: String
    var note: String
    var createdAt: String
}

enum BookingStore {
    static let statusPending = "待确认"
    static let statusConfirmed = "已确认"
    static let statusCompleted = "已完成"
    static let statusCancelled = "已取消"
    static let statusNoShow = "未到"

    static let allStatuses = [statusPending, statusConfirmed, statusCompleted,
                              statusCancelled, statusNoShow]
    static let blockingStatuses = [statusPending, statusConfirmed]
    static let slotMinutes = 30
    static let defaultDurationMinutes = 30

    struct SaveResult {
        var ok = false
        var error = ""
        var id: Int64 = -1
        var conflicts: [BookingRow] = []
    }

    static func rowFromDBRow(_ row: DBRow) -> BookingRow {
        BookingRow(
            id: row.int("id"), memberId: row.int("member_id") == 0 ? -1 : row.int("member_id"),
            staff: row.text("staff"), service: row.text("service"),
            startTime: row.text("start_time"), endTime: row.text("end_time"),
            status: row.text("status"), note: row.text("note"),
            createdAt: row.text("created_at"))
    }

    // MARK: - Time helpers

    private static let minuteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    /// "yyyy-MM-dd HH:mm" → minutes since epoch; nil when unparsable.
    static func toMinutes(_ dt: String) -> Int64? {
        guard let date = minuteFormatter.date(from: dt) else { return nil }
        return Int64(date.timeIntervalSince1970 / 60)
    }

    /// Minutes since epoch → "yyyy-MM-dd HH:mm".
    static func fromMinutes(_ minutes: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(minutes * 60))
        return minuteFormatter.string(from: date)
    }

    /// "yyyy-MM-dd HH:mm" + n minutes (Android `addMinutes`).
    static func addMinutes(_ dt: String, _ n: Int) -> String {
        guard let m = toMinutes(dt) else { return dt }
        return fromMinutes(m + Int64(n))
    }

    // MARK: - Queries

    /// One day's bookings, including a previous-day booking that runs
    /// past midnight into this day (Android `listDay`).
    static func listDay(db: Database, day: String) -> [BookingRow] {
        let dayStart = day + " 00:00"
        let dayEnd = AppDates.addDays(day, 1) + " 00:00"
        return db.query(
            "SELECT * FROM bookings WHERE start_time < ? AND end_time > ? ORDER BY start_time ASC, id ASC",
            bindings: [.text(dayEnd), .text(dayStart)]).map { rowFromDBRow($0) }
    }

    /// Bookings overlapping [startDay, endDay] (closed), by start time.
    static func listRange(db: Database, startDay: String, endDay: String) -> [BookingRow] {
        let from = startDay + " 00:00"
        let to = AppDates.addDays(endDay, 1) + " 00:00"
        return db.query(
            "SELECT * FROM bookings WHERE start_time < ? AND end_time > ? ORDER BY start_time ASC, id ASC",
            bindings: [.text(to), .text(from)]).map { rowFromDBRow($0) }
    }

    /// Upcoming bookings from a datetime, max `limit` (Android list view).
    static func listUpcoming(db: Database, fromDateTime: String, limit: Int) -> [BookingRow] {
        db.query(
            "SELECT * FROM bookings WHERE start_time >= ? ORDER BY start_time ASC, id ASC LIMIT ?",
            bindings: [.text(fromDateTime), .int(Int64(limit))]).map { rowFromDBRow($0) }
    }

    /// Services used before, de-duplicated and sorted (Android
    /// `distinctServices`).
    static func distinctServices(db: Database) -> [String] {
        var seen: [String] = []
        var set = Set<String>()
        for row in db.query(
            "SELECT service FROM bookings WHERE service IS NOT NULL AND service <> '' ORDER BY service ASC") {
            let value = row.text("service").trimmingCharacters(in: .whitespaces)
            if !value.isEmpty && !set.contains(value) {
                set.insert(value)
                seen.append(value)
            }
        }
        return seen.sorted()
    }

    /// The day's 30-minute slot starts ("yyyy-MM-dd HH:mm"), from
    /// business hours; a cross-night window may spill past midnight.
    static func daySlots(day: String, startMin: Int, endMin: Int, nextDay: Bool) -> [String] {
        BusinessHours.slots(startMin: startMin, endMin: endMin, nextDay: nextDay).map { t in
            let slotDay = t >= 1440 ? AppDates.addDays(day, 1) : day
            return slotDay + " " + BusinessHours.formatMinutes(t)
        }
    }

    /// Whether the booking sits inside business hours (Android
    /// `isWithinBusinessHours`).
    static func isWithinBusinessHours(day: String, start: String, end: String,
                                      startMin: Int, endMin: Int, nextDay: Bool) -> Bool {
        guard let dayStart = toMinutes(day + " 00:00"),
              let startAbs = toMinutes(start),
              let endAbs = toMinutes(end) else { return false }
        return BusinessHours.isWithin(startMin: startMin, endMin: endMin, nextDay: nextDay,
                                      dayStartAbs: dayStart, startAbs: startAbs, endAbs: endAbs)
    }

    // MARK: - Conflict check

    /// Bookings overlapping the [start, end] window that block the save: only
    /// 待确认/已确认 block; either side unassigned blocks; two different
    /// assigned staff may run in parallel (Android `findConflicts`).
    static func findConflicts(db: Database, start: String, end: String,
                              staff: String, excludeId: Int64) -> [BookingRow] {
        guard let newStart = toMinutes(start), let newEnd = toMinutes(end),
              newEnd > newStart else { return [] }
        let myStaff = staff.trimmingCharacters(in: .whitespaces)
        let candidates = db.query(
            "SELECT * FROM bookings WHERE (status = ? OR status = ?) AND start_time < ? AND end_time > ?",
            bindings: [.text(statusPending), .text(statusConfirmed),
                       .text(end), .text(start)]).map { rowFromDBRow($0) }
        var out: [BookingRow] = []
        for other in candidates where other.id != excludeId {
            let otherStaff = other.staff.trimmingCharacters(in: .whitespaces)
            if !myStaff.isEmpty && !otherStaff.isEmpty && myStaff != otherStaff { continue }
            guard let oStart = toMinutes(other.startTime),
                  let oEnd = toMinutes(other.endTime) else { continue }
            if newStart < oEnd && oStart < newEnd { out.append(other) }
        }
        return out
    }

    // MARK: - Writes

    static func create(db: Database, booking: BookingRow) -> SaveResult {
        guard let s = toMinutes(booking.startTime), let e = toMinutes(booking.endTime),
              e > s else {
            return SaveResult(ok: false, error: "bad_time")
        }
        let conflicts = findConflicts(db: db, start: booking.startTime, end: booking.endTime,
                                      staff: booking.staff, excludeId: -1)
        if !conflicts.isEmpty {
            return SaveResult(ok: false, error: "conflict", conflicts: conflicts)
        }
        let id = db.nextId("booking")
        let ok = db.execute(
            "INSERT INTO bookings (id, member_id, staff, service, start_time, end_time, status, note, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            bindings: [.int(id),
                       booking.memberId > 0 ? .int(booking.memberId) : .null,
                       .text(booking.staff.trimmingCharacters(in: .whitespaces)),
                       .text(booking.service.trimmingCharacters(in: .whitespaces)),
                       .text(booking.startTime), .text(booking.endTime),
                       .text(isValidStatus(booking.status) ? booking.status : statusPending),
                       .text(booking.note), .text(AppDates.now())])
        return SaveResult(ok: ok, error: ok ? "" : "bad_input", id: ok ? id : -1)
    }

    static func update(db: Database, booking: BookingRow) -> SaveResult {
        guard booking.id > 0 else { return SaveResult(ok: false, error: "bad_input") }
        guard let s = toMinutes(booking.startTime), let e = toMinutes(booking.endTime),
              e > s else {
            return SaveResult(ok: false, error: "bad_time")
        }
        let conflicts = findConflicts(db: db, start: booking.startTime, end: booking.endTime,
                                      staff: booking.staff, excludeId: booking.id)
        if !conflicts.isEmpty {
            return SaveResult(ok: false, error: "conflict", conflicts: conflicts)
        }
        let ok = db.execute(
            "UPDATE bookings SET member_id = ?, staff = ?, service = ?, start_time = ?, end_time = ?, status = ?, note = ? WHERE id = ?",
            bindings: [booking.memberId > 0 ? .int(booking.memberId) : .null,
                       .text(booking.staff.trimmingCharacters(in: .whitespaces)),
                       .text(booking.service.trimmingCharacters(in: .whitespaces)),
                       .text(booking.startTime), .text(booking.endTime),
                       .text(isValidStatus(booking.status) ? booking.status : statusPending),
                       .text(booking.note), .int(booking.id)])
        return SaveResult(ok: ok, error: ok ? "" : "bad_input", id: ok ? booking.id : -1)
    }

    static func setStatus(db: Database, id: Int64, status: String) -> Bool {
        guard id > 0, isValidStatus(status) else { return false }
        return db.execute("UPDATE bookings SET status = ? WHERE id = ?",
                          bindings: [.text(status), .int(id)])
    }

    static func delete(db: Database, id: Int64) -> Bool {
        guard id > 0 else { return false }
        return db.execute("DELETE FROM bookings WHERE id = ?", bindings: [.int(id)])
    }

    static func isValidStatus(_ status: String) -> Bool {
        allStatuses.contains(status)
    }

    static func isBlocking(_ status: String) -> Bool {
        blockingStatuses.contains(status)
    }
}

/// Business-hours math — Swift port of Android `BusinessHours`.
/// Times are minutes since 00:00; end ≤ start means next day.
enum BusinessHours {
    static let defaultStart = "09:00"
    static let defaultEnd = "21:00"

    /// "HH:mm" → minutes; -1 when invalid.
    static func parseMinutes(_ hhmm: String) -> Int {
        let s = hhmm.trimmingCharacters(in: .whitespaces)
        guard s.count == 5, s[s.index(s.startIndex, offsetBy: 2)] == ":" else { return -1 }
        guard let h = Int(s.prefix(2)), let m = Int(s.suffix(2)),
              h >= 0 && h <= 23 && m >= 0 && m <= 59 else { return -1 }
        return h * 60 + m
    }

    /// Minutes → "HH:mm" (mod 1440).
    static func formatMinutes(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    /// Window length in minutes; -1 when invalid. nextDay=true means
    /// the end is on the next day (end == start = 24h).
    static func windowLength(startMin: Int, endMin: Int, nextDay: Bool) -> Int {
        guard startMin >= 0 && startMin < 1440 && endMin >= 0 && endMin < 1440 else { return -1 }
        if nextDay {
            let len = 1440 - startMin + endMin
            return len > 0 ? len : -1
        }
        return endMin > startMin ? endMin - startMin : -1
    }

    static func isValidSetting(startMin: Int, endMin: Int, nextDay: Bool) -> Bool {
        windowLength(startMin: startMin, endMin: endMin, nextDay: nextDay) > 0
    }

    /// Whether the [startAbs, endAbs] window sits inside the day's business window.
    static func isWithin(startMin: Int, endMin: Int, nextDay: Bool,
                         dayStartAbs: Int64, startAbs: Int64, endAbs: Int64) -> Bool {
        let len = windowLength(startMin: startMin, endMin: endMin, nextDay: nextDay)
        guard len > 0, endAbs > startAbs else { return false }
        let openAbs = dayStartAbs + Int64(startMin)
        let closeAbs = openAbs + Int64(len)
        return startAbs >= openAbs && endAbs <= closeAbs
    }

    /// 30-minute slot starts (minutes since 00:00; may exceed 1440
    /// for a cross-night window).
    static func slots(startMin: Int, endMin: Int, nextDay: Bool) -> [Int] {
        let len = windowLength(startMin: startMin, endMin: endMin, nextDay: nextDay)
        guard len > 0 else { return [] }
        var out: [Int] = []
        var t = startMin
        while t + 30 <= startMin + len {
            out.append(t)
            t += 30
        }
        return out
    }
}

fileprivate enum BookingFormTarget: Identifiable {
    case newBooking(start: String)
    case edit(BookingRow)

    var id: String {
        switch self {
        case .newBooking(let start): return "new-\(start)"
        case .edit(let booking): return "edit-\(booking.id)"
        }
    }
}

struct BookingView: View {
    @State private var mode = 0 // 0 day / 1 week / 2 month / 3 list
    @State private var currentDay = AppDates.today()
    @State private var selectedDay = AppDates.today()
    @State private var dayBookings: [BookingRow] = []
    @State private var weekDays: [(day: String, bookings: [BookingRow])] = []
    @State private var monthBookings: [BookingRow] = []
    @State private var upcomingBookings: [BookingRow] = []
    @State private var memberNames: [Int64: String] = [:]
    @State private var formTarget: BookingFormTarget?
    @State private var actionBooking: BookingRow?
    @State private var showActions = false
    @State private var deleteBooking: BookingRow?
    @State private var showDeleteConfirm = false
    @State private var conflicts: [BookingRow] = []
    @State private var showConflict = false
    @State private var showHours = false
    @State private var toast = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                modeBar
                navRow
                newButton
                if !toast.isEmpty { toastBanner }
                contentView
                hoursRow
            }
            .padding(16)
            // Lock the page width to the screen (build #5 lesson: an
            // oversize child can stretch the page past the edges and
            // swallow the padding on a 390pt screen).
            // (containerRelativeFrame needs iOS 17; this app targets iOS 16.)
            .frame(width: UIScreen.main.bounds.width)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear { reload() }
        .sheet(item: $formTarget) { target in
            BookingFormView(target: target, onSave: saveBooking, onCancel: { formTarget = nil })
        }
        .sheet(isPresented: $showHours) {
            BusinessHoursView(onDone: { showHours = false })
        }
        .confirmationDialog(L10n.string("bk_title"), isPresented: $showActions) {
            actionButtons
        } message: {
            if let b = actionBooking {
                Text(actionTitle(b))
            }
        }
        .alert(L10n.string("bk_delete_confirm"), isPresented: $showDeleteConfirm) {
            Button(L10n.string("common_delete"), role: .destructive) {
                if let b = deleteBooking, BookingStore.delete(db: Database.shared, id: b.id) {
                    showToast(L10n.string("bk_deleted"))
                    reload()
                }
            }
            Button(L10n.string("common_cancel"), role: .cancel) {}
        }
        .alert(L10n.string("bk_conflict"), isPresented: $showConflict) {
            Button(L10n.string("common_confirm"), role: .cancel) {}
        } message: {
            Text(conflictText)
        }
    }

    // MARK: - Data

    private func reload() {
        let db = Database.shared
        memberNames = Dictionary(
            uniqueKeysWithValues: MemberStore.loadMembers(db: db).map { ($0.id, $0.name) })
        switch mode {
        case 0:
            dayBookings = BookingStore.listDay(db: db, day: currentDay)
        case 1:
            let start = Self.weekStartOf(currentDay)
            weekDays = AppDates.daysInRange(start, AppDates.addDays(start, 6)).map {
                (day: $0, bookings: BookingStore.listDay(db: db, day: $0))
            }
        case 2:
            monthBookings = BookingStore.listRange(
                db: db, startDay: monthFirstDay(currentDay), endDay: monthLastDay(currentDay))
        default:
            upcomingBookings = BookingStore.listUpcoming(
                db: db, fromDateTime: AppDates.today() + " 00:00", limit: 100)
        }
    }

    private func hours() -> (startMin: Int, endMin: Int, nextDay: Bool) {
        let db = Database.shared
        var startMin = BusinessHours.parseMinutes(
            db.settingValue("hours_start", default: BusinessHours.defaultStart))
        var endMin = BusinessHours.parseMinutes(
            db.settingValue("hours_end", default: BusinessHours.defaultEnd))
        let nextDay = db.settingValue("hours_end_next_day", default: "0") == "1"
        if startMin < 0 { startMin = BusinessHours.parseMinutes(BusinessHours.defaultStart) }
        if endMin < 0 { endMin = BusinessHours.parseMinutes(BusinessHours.defaultEnd) }
        return (startMin, endMin, nextDay)
    }

    private func hoursLabel() -> String {
        let h = hours()
        let range = BusinessHours.formatMinutes(h.startMin) + "–"
            + BusinessHours.formatMinutes(h.endMin)
            + (h.nextDay ? " (" + L10n.string("bk_hours_next_day_short") + ")" : "")
        return L10n.string("bk_hours_title") + " " + range
    }

    private func showToast(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if toast == text { toast = "" }
        }
    }

    private func saveBooking(_ booking: BookingRow, isNew: Bool) -> BookingStore.SaveResult {
        let result = isNew
            ? BookingStore.create(db: Database.shared, booking: booking)
            : BookingStore.update(db: Database.shared, booking: booking)
        if result.ok {
            currentDay = String(booking.startTime.prefix(10))
            selectedDay = currentDay
            showToast(L10n.string("bk_saved"))
            reload()
        } else if result.error == "conflict" {
            conflicts = result.conflicts
            showConflict = true
        } else {
            showToast(L10n.string("bk_bad_time"))
        }
        return result
    }

    private func shift(_ dir: Int) {
        if mode == 1 {
            currentDay = AppDates.addDays(currentDay, 7 * dir)
        } else if mode == 2 {
            currentDay = AppDates.addMonths(currentDay, dir)
        } else {
            currentDay = AppDates.addDays(currentDay, dir)
        }
        selectedDay = currentDay
        reload()
    }

    // MARK: - Header

    private var modeBar: some View {
        let labels = ["bk_day", "bk_week", "bk_month", "bk_list"]
        return HStack(spacing: 8) {
            ForEach(labels.indices, id: \.self) { index in
                Button(L10n.string(labels[index])) {
                    mode = index
                    reload()
                }
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(index == mode ? Brand.deepGreen : Color(.systemBackground))
                .foregroundColor(index == mode ? .white : Color(.label))
                .cornerRadius(10)
            }
        }
    }

    private var navRow: some View {
        HStack(spacing: 6) {
            navArrow("‹") { shift(-1) }
            Button(L10n.string("bk_today")) {
                currentDay = AppDates.today()
                selectedDay = currentDay
                reload()
            }
            .font(.subheadline)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(Color(.systemBackground))
            .foregroundColor(Color(.label))
            .cornerRadius(8)
            navArrow("›") { shift(1) }
            Text(navTitle)
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
        }
    }

    private func navArrow(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .font(.title3)
            .frame(width: 44, height: 36)
            .background(Color(.systemBackground))
            .foregroundColor(Color(.label))
            .cornerRadius(8)
    }

    private var navTitle: String {
        switch mode {
        case 0:
            return currentDay + "  " + weekdayAbbr(currentDay)
        case 1:
            let start = Self.weekStartOf(currentDay)
            return String(format: L10n.string("bk_week_fmt"), start, AppDates.addDays(start, 6))
        case 2:
            return monthTitle(currentDay)
        default:
            return L10n.string("bk_list")
        }
    }

    private var newButton: some View {
        Button(L10n.string("bk_new")) {
            formTarget = .newBooking(start: currentDay + " 10:00")
        }
        .buttonStyle(.borderedProminent)
        .tint(Brand.deepGreen)
        .frame(maxWidth: .infinity)
    }

    private var toastBanner: some View {
        Text(toast)
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Brand.deepGreen)
            .cornerRadius(8)
    }

    private var hoursRow: some View {
        HStack {
            Text(hoursLabel())
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer()
            Button(L10n.string("bk_hours_edit")) { showHours = true }
                .font(.subheadline)
                .foregroundColor(Brand.deepGreen)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
    }

    // MARK: - Mode content

    @ViewBuilder
    private var contentView: some View {
        switch mode {
        case 0: dayView
        case 1: weekView
        case 2: monthView
        default: listView
        }
    }

    private var dayView: some View {
        let h = hours()
        let slots = BookingStore.daySlots(day: currentDay, startMin: h.startMin,
                                          endMin: h.endMin, nextDay: h.nextDay)
        return VStack(spacing: 8) {
            Text(String(format: L10n.string("bk_day_summary"), dayBookings.count))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if slots.isEmpty {
                emptyText(L10n.string("bk_empty"))
            } else {
                ForEach(slots, id: \.self) { slot in
                    daySlotRow(slot)
                }
            }
        }
    }

    private func daySlotRow(_ slot: String) -> some View {
        let slotTime = String(slot.dropFirst(11))
        let matches = dayBookings.filter { $0.startTime == slot }
        return HStack(alignment: .top, spacing: 10) {
            Text(slotTime)
                .font(.subheadline)
                .bold()
                .frame(width: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                if matches.isEmpty {
                    Text(L10n.string("bk_tap_to_book"))
                        .font(.subheadline)
                        .foregroundColor(Brand.deepGreen)
                } else {
                    ForEach(matches) { booking in
                        bookingCard(booking, showDate: false)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .onTapGesture { formTarget = .newBooking(start: slot) }
    }

    private var weekView: some View {
        VStack(spacing: 12) {
            ForEach(weekDays.indices, id: \.self) { index in
                weekDayCard(weekDays[index].day, bookings: weekDays[index].bookings)
            }
        }
    }

    private func weekDayCard(_ day: String, bookings: [BookingRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(dateChip(day))
                    .font(.subheadline)
                    .bold()
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(day == AppDates.today() ? Brand.deepGreen : Color(.darkGray))
                    .cornerRadius(12)
                Text(bookings.isEmpty
                     ? L10n.string("bk_week_free")
                     : String(format: L10n.string("bk_week_bookings"), bookings.count))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Button("＋") { formTarget = .newBooking(start: day + " 10:00") }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 2)
                    .background(Brand.deepGreen)
                    .cornerRadius(8)
            }
            .onTapGesture { formTarget = .newBooking(start: day + " 10:00") }
            if bookings.isEmpty {
                Text(L10n.string("bk_tap_to_book"))
                    .font(.subheadline)
                    .foregroundColor(Brand.deepGreen)
                    .padding(.top, 2)
                    .onTapGesture { formTarget = .newBooking(start: day + " 10:00") }
            } else {
                ForEach(bookings) { booking in
                    bookingCard(booking, showDate: false)
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
    }

    private func dateChip(_ day: String) -> String {
        String(day.dropFirst(5)) + " " + weekdayAbbr(day)
    }

    private var monthView: some View {
        VStack(spacing: 12) {
            weekdayHeader
            monthGrid
            selectedDaySection
        }
    }

    private var weekdayHeader: some View {
        let keys = ["bk_wd_sun", "bk_wd_mon", "bk_wd_tue", "bk_wd_wed",
                    "bk_wd_thu", "bk_wd_fri", "bk_wd_sat"]
        return HStack(spacing: 0) {
            ForEach(keys, id: \.self) { key in
                Text(L10n.string(key))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(monthCells, id: \.self) { day in
                if let day {
                    let dayNum = Int(day.dropFirst(8)) ?? 0
                    let has = monthBookings.contains { $0.startTime.hasPrefix(day) }
                    Button(has ? "\(dayNum) •" : "\(dayNum)") {
                        selectedDay = day
                        reload()
                    }
                    .font(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .foregroundColor(day == selectedDay ? .white : Color(.label))
                    .background(day == selectedDay ? Brand.deepGreen : Color.clear)
                    .cornerRadius(8)
                } else {
                    Color.clear.frame(height: 40)
                }
            }
        }
    }

    /// Calendar cells for the current month (nil = leading/trailing blank).
    private var monthCells: [String?] {
        guard let first = AppDates.parseDay(monthFirstDay(currentDay)) else { return [] }
        let comps = Calendar.current.dateComponents([.year, .month], from: first)
        guard let year = comps.year, let month = comps.month,
              let daysInMonth = Calendar.current.range(of: .day, in: .month, for: first)?.count
        else { return [] }
        let firstWeekday = Calendar.current.component(.weekday, from: first) // 1 = Sunday
        var cells: [String?] = Array(repeating: nil, count: firstWeekday - 1)
        for day in 1...daysInMonth {
            cells.append(String(format: "%04d-%02d-%02d", year, month, day))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private var selectedDaySection: some View {
        let list = BookingStore.listDay(db: Database.shared, day: selectedDay)
        return VStack(alignment: .leading, spacing: 8) {
            Text(selectedDay + "  " + weekdayAbbr(selectedDay))
                .font(.headline)
            if list.isEmpty {
                emptyText(L10n.string("bk_empty"))
            } else {
                ForEach(list) { booking in
                    bookingCard(booking, showDate: true)
                }
            }
        }
    }

    private var listView: some View {
        VStack(spacing: 8) {
            if upcomingBookings.isEmpty {
                emptyText(L10n.string("bk_empty_upcoming"))
            } else {
                ForEach(upcomingBookings) { booking in
                    bookingCard(booking, showDate: true)
                }
            }
        }
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Booking card + actions

    private func bookingCard(_ booking: BookingRow, showDate: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(cardTime(booking, showDate: showDate))
                    .font(.subheadline)
                    .bold()
                    .lineLimit(1)
                Spacer()
                Text(statusText(booking.status))
                    .font(.caption)
                    .bold()
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(statusColor(booking.status))
                    .cornerRadius(12)
            }
            Text(cardInfo(booking))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
            if !booking.note.isEmpty {
                Text(booking.note)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .onTapGesture {
            actionBooking = booking
            showActions = true
        }
    }

    private func cardTime(_ booking: BookingRow, showDate: Bool) -> String {
        let time = timePart(booking.startTime) + "–" + timePart(booking.endTime)
        if showDate { return datePart(booking.startTime) + "  " + time }
        return time
    }

    private func cardInfo(_ booking: BookingRow) -> String {
        let member = booking.memberId > 0
            ? (memberNames[booking.memberId] ?? L10n.string("bk_walkin"))
            : L10n.string("bk_walkin")
        let staff = booking.staff.isEmpty ? L10n.string("bk_no_staff") : booking.staff
        return member + " · " + staff
            + (booking.service.isEmpty ? "" : " · " + booking.service)
    }

    private func actionTitle(_ booking: BookingRow) -> String {
        booking.startTime + "  " + (memberNames[booking.memberId] ?? L10n.string("bk_walkin"))
    }

    @ViewBuilder
    private var actionButtons: some View {
        if let booking = actionBooking {
            if booking.status == BookingStore.statusPending {
                Button(L10n.string("bk_action_confirm")) {
                    _ = BookingStore.setStatus(db: Database.shared, id: booking.id,
                                               status: BookingStore.statusConfirmed)
                    reload()
                }
            }
            if booking.status == BookingStore.statusPending
                || booking.status == BookingStore.statusConfirmed {
                Button(L10n.string("bk_action_complete")) {
                    _ = BookingStore.setStatus(db: Database.shared, id: booking.id,
                                               status: BookingStore.statusCompleted)
                    reload()
                }
                Button(L10n.string("bk_action_noshow")) {
                    _ = BookingStore.setStatus(db: Database.shared, id: booking.id,
                                               status: BookingStore.statusNoShow)
                    reload()
                }
                Button(L10n.string("bk_action_cancel")) {
                    _ = BookingStore.setStatus(db: Database.shared, id: booking.id,
                                               status: BookingStore.statusCancelled)
                    reload()
                }
            }
            Button(L10n.string("bk_action_edit")) {
                formTarget = .edit(booking)
            }
            Button(L10n.string("common_delete"), role: .destructive) {
                deleteBooking = booking
                showDeleteConfirm = true
            }
        }
    }

    private var conflictText: String {
        conflicts.map { conflict in
            let staff = conflict.staff.isEmpty ? L10n.string("bk_no_staff") : conflict.staff
            return String(format: L10n.string("bk_conflict_item_fmt"),
                          datePart(conflict.startTime), timePart(conflict.startTime),
                          timePart(conflict.endTime), staff, statusText(conflict.status))
        }.joined(separator: "\n")
    }

    // MARK: - Small helpers

    private func statusText(_ status: String) -> String {
        switch status {
        case BookingStore.statusConfirmed: return L10n.string("bk_status_confirmed")
        case BookingStore.statusCompleted: return L10n.string("bk_status_completed")
        case BookingStore.statusCancelled: return L10n.string("bk_status_cancelled")
        case BookingStore.statusNoShow: return L10n.string("bk_status_noshow")
        default: return L10n.string("bk_status_pending")
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case BookingStore.statusConfirmed: return Brand.deepGreen
        case BookingStore.statusCompleted:
            return Color(red: 0x6B / 255, green: 0x72 / 255, blue: 0x80 / 255)
        case BookingStore.statusCancelled:
            return Color(red: 0xDC / 255, green: 0x26 / 255, blue: 0x26 / 255)
        case BookingStore.statusNoShow:
            return Color(red: 0x9C / 255, green: 0xA3 / 255, blue: 0xAF / 255)
        default:
            return Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x06 / 255)
        }
    }

    private static func weekStartOf(_ day: String) -> String {
        guard let date = AppDates.parseDay(day) else { return day }
        let weekday = Calendar.current.component(.weekday, from: date)
        let shift = weekday == 1 ? -6 : -(weekday - 2)
        guard let monday = Calendar.current.date(byAdding: .day, value: shift, to: date) else {
            return day
        }
        return AppDates.dayString(monday)
    }

    private func weekdayAbbr(_ day: String) -> String {
        guard let date = AppDates.parseDay(day) else { return "" }
        let weekday = Calendar.current.component(.weekday, from: date) // 1 = Sunday
        let keys = ["bk_wd_sun", "bk_wd_mon", "bk_wd_tue", "bk_wd_wed",
                    "bk_wd_thu", "bk_wd_fri", "bk_wd_sat"]
        return L10n.string(keys[weekday - 1])
    }

    private func monthTitle(_ day: String) -> String {
        guard let date = AppDates.parseDay(day) else { return day }
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        guard let year = comps.year, let month = comps.month else { return day }
        if L10n.current == .zhHans {
            return String(format: L10n.string("bk_month_fmt"), year, month)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private func monthFirstDay(_ day: String) -> String {
        String(day.prefix(7)) + "-01"
    }

    private func monthLastDay(_ day: String) -> String {
        guard let date = AppDates.parseDay(monthFirstDay(day)),
              let range = Calendar.current.range(of: .day, in: .month, for: date) else {
            return day
        }
        return String(day.prefix(7)) + "-" + String(format: "%02d", range.count)
    }
}

/// "yyyy-MM-dd HH:mm" → date part; malformed input passes through.
private func datePart(_ dt: String) -> String {
    dt.count >= 10 ? String(dt.prefix(10)) : dt
}

/// "yyyy-MM-dd HH:mm" → "HH:mm" part; malformed input passes through.
private func timePart(_ dt: String) -> String {
    dt.count >= 16 ? String(dt.dropFirst(11)) : dt
}

// MARK: - Booking form

/// New / edit booking sheet. Member is optional (walk-in); staff and
/// service are pickers with a custom-text last option; start/end are
/// date+time pickers (changing start moves end +30 min, Android fix2).
struct BookingFormView: View {
    let target: BookingFormTarget
    let onSave: (BookingRow, Bool) -> BookingStore.SaveResult
    let onCancel: () -> Void

    @State private var selectedMember: MemberRow?
    @State private var staffSelection: String
    @State private var staffCustom = ""
    @State private var serviceSelection: String
    @State private var serviceCustom = ""
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var note: String
    @State private var errorText = ""

    private let staffOptions: [String]
    private let serviceOptions: [String]

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    init(target: BookingFormTarget,
         onSave: @escaping (BookingRow, Bool) -> BookingStore.SaveResult,
         onCancel: @escaping () -> Void) {
        self.target = target
        self.onSave = onSave
        self.onCancel = onCancel
        let db = Database.shared
        var staff = [L10n.string("bk_no_staff")]
        staff += db.query("SELECT username FROM users ORDER BY username")
            .map { $0.text("username") }.filter { !$0.isEmpty }
        staff.append(L10n.string("bk_staff_custom"))
        self.staffOptions = staff
        var services = BookingStore.distinctServices(db: db)
        services += db.query("SELECT name FROM products WHERE active = 1 ORDER BY name")
            .map { $0.text("name") }.filter { !$0.isEmpty }
        services += db.query("SELECT DISTINCT category FROM products WHERE category <> '' ORDER BY category")
            .map { $0.text("category") }.filter { !$0.isEmpty }
        var seen = Set<String>()
        services = services.filter { seen.insert($0).inserted }
        services.append(L10n.string("bk_service_custom"))
        self.serviceOptions = services

        switch target {
        case .newBooking(let start):
            let startDate = Self.dateTimeFormatter.date(from: start)
                ?? AppDates.parseDay(AppDates.today()) ?? Date()
            _startDate = State(initialValue: startDate)
            _endDate = State(initialValue: Calendar.current.date(
                byAdding: .minute, value: BookingStore.defaultDurationMinutes,
                to: startDate) ?? startDate)
            _staffSelection = State(initialValue: staff[0])
            _serviceSelection = State(initialValue: services[0])
            _note = State(initialValue: "")
            _selectedMember = State(initialValue: nil)
        case .edit(let booking):
            let startDate = Self.dateTimeFormatter.date(from: booking.startTime) ?? Date()
            let endDate = Self.dateTimeFormatter.date(from: booking.endTime) ?? Date()
            _startDate = State(initialValue: startDate)
            _endDate = State(initialValue: endDate)
            _note = State(initialValue: booking.note)
            _selectedMember = State(initialValue: booking.memberId > 0
                ? MemberStore.memberById(db: db, id: booking.memberId) : nil)
            if booking.staff.isEmpty {
                _staffSelection = State(initialValue: staff[0])
            } else if let index = staff.firstIndex(of: booking.staff) {
                _staffSelection = State(initialValue: staff[index])
            } else {
                _staffSelection = State(initialValue: staff[staff.count - 1])
                _staffCustom = State(initialValue: booking.staff)
            }
            if booking.service.isEmpty {
                _serviceSelection = State(initialValue: services[0])
            } else if let index = services.firstIndex(of: booking.service) {
                _serviceSelection = State(initialValue: services[index])
            } else {
                _serviceSelection = State(initialValue: services[services.count - 1])
                _serviceCustom = State(initialValue: booking.service)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    memberSection
                    staffSection
                    serviceSection
                    timeSection
                    noteSection
                    if !errorText.isEmpty {
                        Text(errorText)
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(formTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common_cancel")) { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("common_save")) { save() }
                        .bold()
                }
            }
        }
    }

    private var formTitle: String {
        switch target {
        case .newBooking: return L10n.string("bk_new")
        case .edit: return L10n.string("bk_action_edit")
        }
    }

    private var memberSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("bk_member"))
                .font(.subheadline)
                .foregroundColor(.secondary)
            MemberPickerField(selected: $selectedMember)
        }
    }

    private var staffSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("bk_staff"))
                .font(.subheadline)
                .foregroundColor(.secondary)
            Picker("", selection: $staffSelection) {
                ForEach(staffOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            if staffSelection == staffOptions[staffOptions.count - 1] {
                TextField(L10n.string("bk_staff_custom_hint"), text: $staffCustom)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var serviceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("bk_service"))
                .font(.subheadline)
                .foregroundColor(.secondary)
            Picker("", selection: $serviceSelection) {
                ForEach(serviceOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            if serviceSelection == serviceOptions[serviceOptions.count - 1] {
                TextField(L10n.string("bk_service_custom_hint"), text: $serviceCustom)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("bk_start"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                DatePicker("", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .onChange(of: startDate) { newValue in
                        endDate = Calendar.current.date(
                            byAdding: .minute, value: BookingStore.defaultDurationMinutes,
                            to: newValue) ?? newValue
                    }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("bk_end"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                DatePicker("", selection: $endDate, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
            }
            Button(L10n.string("bk_plus_30")) {
                endDate = Calendar.current.date(byAdding: .minute, value: 30, to: endDate)
                    ?? endDate
            }
            .font(.subheadline)
            .foregroundColor(Brand.deepGreen)
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.string("bk_note"))
                .font(.subheadline)
                .foregroundColor(.secondary)
            TextField("", text: $note)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func staffValue() -> String {
        if staffSelection == staffOptions[staffOptions.count - 1] {
            return staffCustom.trimmingCharacters(in: .whitespaces)
        }
        if staffSelection == staffOptions[0] { return "" }
        return staffSelection
    }

    private func serviceValue() -> String {
        if serviceSelection == serviceOptions[serviceOptions.count - 1] {
            return serviceCustom.trimmingCharacters(in: .whitespaces)
        }
        return serviceSelection
    }

    private func save() {
        guard endDate > startDate else {
            errorText = L10n.string("bk_bad_time")
            return
        }
        let startText = Self.dateTimeFormatter.string(from: startDate)
        let endText = Self.dateTimeFormatter.string(from: endDate)
        let db = Database.shared
        let startMin = BusinessHours.parseMinutes(
            db.settingValue("hours_start", default: BusinessHours.defaultStart))
        let endMin = BusinessHours.parseMinutes(
            db.settingValue("hours_end", default: BusinessHours.defaultEnd))
        let nextDay = db.settingValue("hours_end_next_day", default: "0") == "1"
        let day = String(startText.prefix(10))
        guard BookingStore.isWithinBusinessHours(
            day: day, start: startText, end: endText,
            startMin: startMin, endMin: endMin, nextDay: nextDay) else {
            errorText = L10n.string("bk_outside_hours")
            return
        }
        let isNew: Bool
        let booking: BookingRow
        switch target {
        case .newBooking:
            isNew = true
            booking = BookingRow(id: -1, memberId: selectedMember?.id ?? -1,
                                 staff: staffValue(), service: serviceValue(),
                                 startTime: startText, endTime: endText,
                                 status: BookingStore.statusPending,
                                 note: note.trimmingCharacters(in: .whitespaces),
                                 createdAt: "")
        case .edit(let existing):
            isNew = false
            booking = BookingRow(id: existing.id, memberId: selectedMember?.id ?? -1,
                                 staff: staffValue(), service: serviceValue(),
                                 startTime: startText, endTime: endText,
                                 status: existing.status,
                                 note: note.trimmingCharacters(in: .whitespaces),
                                 createdAt: existing.createdAt)
        }
        _ = onSave(booking, isNew)
        onCancel()
    }
}

// MARK: - Business hours editor

/// Business-hours settings (Android has them in SettingsPage; iOS
/// Settings is still a placeholder, so the Booking page carries the
/// editor). Start/end time pickers + "closes next day" toggle.
struct BusinessHoursView: View {
    let onDone: () -> Void

    @State private var startDate: Date
    @State private var endDate: Date
    @State private var nextDay: Bool
    @State private var errorText = ""

    init(onDone: @escaping () -> Void) {
        self.onDone = onDone
        let db = Database.shared
        let startMin = BusinessHours.parseMinutes(
            db.settingValue("hours_start", default: BusinessHours.defaultStart))
        let endMin = BusinessHours.parseMinutes(
            db.settingValue("hours_end", default: BusinessHours.defaultEnd))
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        _startDate = State(initialValue: calendar.date(
            byAdding: .minute, value: max(0, startMin), to: today) ?? today)
        _endDate = State(initialValue: calendar.date(
            byAdding: .minute, value: max(0, endMin), to: today) ?? today)
        _nextDay = State(initialValue:
            db.settingValue("hours_end_next_day", default: "0") == "1")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(L10n.string("bk_hours_start"), selection: $startDate,
                               displayedComponents: .hourAndMinute)
                    DatePicker(L10n.string("bk_hours_end"), selection: $endDate,
                               displayedComponents: .hourAndMinute)
                    Toggle(L10n.string("bk_hours_next_day"), isOn: $nextDay)
                }
                if !errorText.isEmpty {
                    Text(errorText)
                        .font(.subheadline)
                        .foregroundColor(.red)
                }
            }
            .navigationTitle(L10n.string("bk_hours_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common_cancel")) { onDone() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("common_save")) { save() }
                        .bold()
                }
            }
        }
    }

    private func save() {
        let calendar = Calendar.current
        let startMin = calendar.component(.hour, from: startDate) * 60
            + calendar.component(.minute, from: startDate)
        let endMin = calendar.component(.hour, from: endDate) * 60
            + calendar.component(.minute, from: endDate)
        guard BusinessHours.isValidSetting(startMin: startMin, endMin: endMin,
                                           nextDay: nextDay) else {
            errorText = L10n.string("bk_hours_invalid")
            return
        }
        let db = Database.shared
        _ = db.setSetting("hours_start", value: BusinessHours.formatMinutes(startMin))
        _ = db.setSetting("hours_end", value: BusinessHours.formatMinutes(endMin))
        _ = db.setSetting("hours_end_next_day", value: nextDay ? "1" : "0")
        onDone()
    }
}
