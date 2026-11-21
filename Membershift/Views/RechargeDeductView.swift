import SwiftUI

/// Recharge & Deduct — mirrors Android `RechargePage` (fix2 three modes)
/// + `CheckoutEngine` (earn / recharge / deduct / adjust, in
/// `PointsEngine`).
///
/// - 3 modes: 充值 (earn + recharge cards) / 充值扣减 / 积分调整
///   (manager only; the adjust tab is hidden otherwise, like Android).
/// - Member picker: name/phone search, max 8 suggestions, selected
///   member card (points · balance · total spent).
/// - Earn: amount + live "可得积分 ≈ X 分" preview, then earn.
/// - Recharge: amount + live bonus preview ("充 X 赠 Y，到账 Z" /
///   "再充到 X 可多送" / "当前无赠送档位"), then recharge.
/// - Deduct: amount + live "扣减后余额 X · 本次可得 +Y 分" preview;
///   before deduct, a member with a PIN must enter the 4-digit PIN
///   (Android fix5; wrong PIN clears and stays open for retry); a
///   member without a PIN deducts directly with a set-a-PIN tip.
/// - Adjust: points delta (+100 / -50) + optional reason; points must
///   stay ≥ 0.
/// - No printer on iOS yet: no print / reprint buttons (Android's
///   "扣减并打印" is just "扣减" here); the deduct button label says so.
struct RechargeDeductView: View {
    @EnvironmentObject private var appState: AppState

    @State private var mode = 0 // 0 topup / 1 deduct / 2 adjust
    @State private var selectedMember: MemberRow?
    @State private var earnAmount = ""
    @State private var rechargeAmount = ""
    @State private var deductAmount = ""
    @State private var adjustPoints = ""
    @State private var adjustReason = ""
    @State private var message = ""
    @State private var messageIsError = false
    @State private var showPin = false
    @State private var pendingDeductAmount = 0.0

    private var isManager: Bool { appState.currentUser?.isManager ?? false }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                modeBar
                memberCard
                if !message.isEmpty { messageBanner }
                if mode == 0 {
                    earnCard
                    rechargeCard
                } else if mode == 1 {
                    deductCard
                } else {
                    adjustCard
                }
            }
            .padding(16)
            // Lock the page width to the screen (build #5 lesson).
            .containerRelativeFrame(.horizontal)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            if mode == 2 && !isManager { mode = 0 }
        }
        .sheet(isPresented: $showPin) {
            if let member = selectedMember {
                PinPromptView(member: member) { pin in
                    verifyPinAndDeduct(member: member, pin: pin)
                } onCancel: {
                    showPin = false
                }
            }
        }
    }

    // MARK: - Mode bar + member

    private var modeBar: some View {
        HStack(spacing: 8) {
            modeButton(index: 0, key: "rc_mode_topup")
            modeButton(index: 1, key: "rc_mode_deduct")
            if isManager {
                modeButton(index: 2, key: "rc_mode_adjust")
            }
        }
    }

    private func modeButton(index: Int, key: String) -> some View {
        Button(L10n.string(key)) { mode = index }
            .font(.subheadline)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(index == mode ? Brand.deepGreen : Color(.systemBackground))
            .foregroundColor(index == mode ? .white : Color(.label))
            .cornerRadius(10)
    }

    private var memberCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("bk_member"))
                .font(.subheadline)
                .foregroundColor(.secondary)
            MemberPickerField(selected: $selectedMember)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
    }

    private var messageBanner: some View {
        Text(message)
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(messageIsError ? Color.red : Brand.deepGreen)
            .cornerRadius(8)
            .frame(maxWidth: .infinity)
    }

    private func showMessage(_ text: String, isError: Bool = false) {
        message = text
        messageIsError = isError
    }

    private var op: String { appState.currentUser?.username ?? "admin" }

    private func refreshMember() {
        if let member = selectedMember {
            selectedMember = MemberStore.memberById(db: Database.shared, id: member.id)
        }
    }

    private func multiplier(for member: MemberRow) -> Double {
        let tiers = MemberStore.loadTiers(db: Database.shared)
        return MemberStore.tierForSpent(tiers: tiers, spent: member.totalSpent)?.multiplier ?? 1
    }

    private func trimNum(_ value: Double) -> String {
        if value == floor(value) { return String(format: "%.0f", value) }
        return String(format: "%.1f", value)
    }

    // MARK: - Earn card

    private var earnCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("rc_earn_title"))
                .font(.headline)
            TextField(L10n.string("rc_earn_amount"), text: $earnAmount)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
            if !earnPreview.isEmpty {
                Text(earnPreview)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Button(L10n.string("rc_earn_btn")) { doEarn() }
                .buttonStyle(.borderedProminent)
                .tint(Brand.deepGreen)
                .frame(maxWidth: .infinity)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
    }

    private var earnPreview: String {
        guard let member = selectedMember else {
            return L10n.string("rc_earn_preview_none")
        }
        guard let amount = Double(earnAmount), amount > 0 else { return "" }
        let pts = PointsEngine.earnFor(
            amount: amount, earnRate: PointsEngine.earnRate(db: Database.shared),
            multiplier: multiplier(for: member))
        let cur = PointsEngine.currency(db: Database.shared)
        return String(format: L10n.string("rc_earn_preview"),
                      PointsEngine.money(amount, currency: cur), pts, trimNum(multiplier(for: member)))
    }

    private func doEarn() {
        guard let member = selectedMember else {
            showMessage(L10n.string("err_need_member"), isError: true)
            return
        }
        guard let amount = Double(earnAmount), amount > 0 else {
            showMessage(L10n.string("err_need_amount"), isError: true)
            return
        }
        let result = PointsEngine.earn(db: Database.shared, memberId: member.id,
                                       amount: amount, op: op)
        if result.ok {
            showMessage(String(format: L10n.string("rc_earn_ok"), result.points))
            earnAmount = ""
            refreshMember()
        } else {
            showMessage(PointsEngine.errorText(result.error), isError: true)
        }
    }

    // MARK: - Recharge card

    private var rechargeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("rc_recharge_title"))
                .font(.headline)
            TextField(L10n.string("rc_recharge_amount"), text: $rechargeAmount)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
            if !rechargePreview.isEmpty {
                Text(rechargePreview)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Button(L10n.string("rc_recharge_btn")) { doRecharge() }
                .buttonStyle(.borderedProminent)
                .tint(Brand.deepGreen)
                .frame(maxWidth: .infinity)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
    }

    private var rechargePreview: String {
        guard let amount = Double(rechargeAmount), amount > 0 else { return "" }
        let tiers = PointsEngine.rechargeTiers(db: Database.shared)
        let bonus = PointsEngine.bonusFor(tiers: tiers, amount: amount)
        let cur = PointsEngine.currency(db: Database.shared)
        if bonus > 0 {
            return String(format: L10n.string("rc_bonus_reach"),
                          PointsEngine.money(amount, currency: cur),
                          PointsEngine.money(bonus, currency: cur),
                          PointsEngine.money(amount + bonus, currency: cur))
        }
        if let next = PointsEngine.nextTier(tiers: tiers, amount: amount) {
            return String(format: L10n.string("rc_bonus_next"),
                          PointsEngine.money(next.0, currency: cur))
        }
        return L10n.string("rc_bonus_none")
    }

    private func doRecharge() {
        guard let member = selectedMember else {
            showMessage(L10n.string("err_need_member"), isError: true)
            return
        }
        guard let amount = Double(rechargeAmount), amount > 0 else {
            showMessage(L10n.string("err_need_amount"), isError: true)
            return
        }
        let result = PointsEngine.recharge(db: Database.shared, memberId: member.id,
                                           amount: amount, op: op)
        if result.ok {
            let cur = PointsEngine.currency(db: Database.shared)
            showMessage(String(format: L10n.string("rc_recharge_ok"),
                               PointsEngine.money(result.credited, currency: cur)))
            rechargeAmount = ""
            refreshMember()
        } else {
            showMessage(PointsEngine.errorText(result.error), isError: true)
        }
    }

    // MARK: - Deduct card

    private var deductCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("rc_mode_deduct"))
                .font(.headline)
            TextField(L10n.string("rc_deduct_amount"), text: $deductAmount)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
            if !deductPreview.isEmpty {
                Text(deductPreview)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if let member = selectedMember, member.pinHash.isEmpty {
                Text(L10n.string("rc_pin_no_pin_tip"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Button(L10n.string("rc_deduct_btn")) { doDeduct() }
                .buttonStyle(.borderedProminent)
                .tint(Brand.deepGreen)
                .frame(maxWidth: .infinity)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
    }

    private var deductPreview: String {
        guard let member = selectedMember else {
            return L10n.string("rc_earn_preview_none")
        }
        guard let amount = Double(deductAmount), amount > 0 else { return "" }
        if amount > member.balance {
            return L10n.string("err_balance_not_enough")
        }
        let pts = PointsEngine.earnFor(
            amount: amount, earnRate: PointsEngine.earnRate(db: Database.shared),
            multiplier: multiplier(for: member))
        let cur = PointsEngine.currency(db: Database.shared)
        return String(format: L10n.string("rc_deduct_preview_fmt"),
                      PointsEngine.money(member.balance - amount, currency: cur), pts)
    }

    /// Deduct entry point: members with a PIN must enter it first
    /// (Android fix5); members without one deduct directly.
    private func doDeduct() {
        guard let member = selectedMember else {
            showMessage(L10n.string("err_need_member"), isError: true)
            return
        }
        guard let amount = Double(deductAmount), amount > 0 else {
            showMessage(L10n.string("err_need_amount"), isError: true)
            return
        }
        if amount > member.balance {
            showMessage(L10n.string("err_balance_not_enough"), isError: true)
            return
        }
        if member.pinHash.isEmpty {
            runDeduct(member: member, amount: amount)
            return
        }
        pendingDeductAmount = amount
        showPin = true
    }

    /// Called by the PIN sheet: returns true when the PIN is right
    /// (sheet dismisses); false keeps the sheet open for retry.
    private func verifyPinAndDeduct(member: MemberRow, pin: String) -> Bool {
        let hash = Auth.hashPassword(pin, salt: member.pinSalt)
        guard hash == member.pinHash else { return false }
        showPin = false
        runDeduct(member: member, amount: pendingDeductAmount)
        return true
    }

    private func runDeduct(member: MemberRow, amount: Double) {
        let result = PointsEngine.deductBalance(db: Database.shared, memberId: member.id,
                                                amount: amount, op: op)
        if result.ok {
            let cur = PointsEngine.currency(db: Database.shared)
            showMessage(String(format: L10n.string("rc_deduct_ok"),
                               PointsEngine.money(amount, currency: cur)))
            deductAmount = ""
            refreshMember()
        } else {
            showMessage(PointsEngine.errorText(result.error), isError: true)
        }
    }

    // MARK: - Adjust card (manager only)

    private var adjustCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("rc_adjust_title"))
                .font(.headline)
            TextField(L10n.string("rc_adjust_points"), text: $adjustPoints)
                .keyboardType(.numbersAndPunctuation)
                .textFieldStyle(.roundedBorder)
            TextField(L10n.string("rc_adjust_reason"), text: $adjustReason)
                .textFieldStyle(.roundedBorder)
            Button(L10n.string("rc_adjust_btn")) { doAdjust() }
                .buttonStyle(.borderedProminent)
                .tint(Brand.deepGreen)
                .frame(maxWidth: .infinity)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
    }

    private func doAdjust() {
        guard isManager else {
            showMessage(L10n.string("rc_adjust_admin_only"), isError: true)
            return
        }
        guard let member = selectedMember else {
            showMessage(L10n.string("err_need_member"), isError: true)
            return
        }
        guard let delta = Int(adjustPoints), delta != 0 else {
            showMessage(L10n.string("err_need_amount"), isError: true)
            return
        }
        if member.points + Int64(delta) < 0 {
            showMessage(L10n.string("rc_adjust_error_negative"), isError: true)
            return
        }
        let result = PointsEngine.adjust(db: Database.shared, memberId: member.id,
                                         delta: delta,
                                         reason: adjustReason.trimmingCharacters(in: .whitespaces),
                                         op: op)
        if result.ok {
            showMessage(L10n.string("rc_adjust_ok"))
            adjustPoints = ""
            adjustReason = ""
            refreshMember()
        } else {
            showMessage(PointsEngine.errorText(result.error), isError: true)
        }
    }
}

// MARK: - Shared member picker

/// Member search + select, shared by the Booking form and the
/// Recharge page (Android `MemberPicker`: name/phone search, max 8
/// suggestions; tap to select; the selected card shows points ·
/// balance · total spent, with a clear button).
struct MemberPickerField: View {
    @Binding var selected: MemberRow?
    @State private var searchText = ""
    @State private var suggestions: [MemberRow] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let member = selected {
                selectedCard(member)
            } else {
                TextField(L10n.string("mem_search_hint"), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: searchText) { newValue in
                        searchMembers(newValue)
                    }
                if !suggestions.isEmpty {
                    suggestionList
                }
            }
        }
    }

    private func selectedCard(_ member: MemberRow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(member.name)
                    .font(.headline)
                Text(member.phone)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(memberLine(member))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                selected = nil
                searchText = ""
                suggestions = []
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color(.systemGreen).opacity(0.12))
        .cornerRadius(10)
    }

    private func memberLine(_ member: MemberRow) -> String {
        let cur = PointsEngine.currency(db: Database.shared)
        return String(format: L10n.string("mem_points_fmt"), Int(member.points))
            + " · " + String(format: L10n.string("mem_balance_fmt"),
                            PointsEngine.money(member.balance, currency: cur))
            + " · " + String(format: L10n.string("mem_spent_fmt"),
                            PointsEngine.money(member.totalSpent, currency: cur))
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions) { member in
                Button {
                    selected = member
                    searchText = ""
                    suggestions = []
                } label: {
                    HStack {
                        Text(member.name)
                            .font(.subheadline)
                        Text(member.phone)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
        .padding(.horizontal, 8)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }

    private func searchMembers(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            suggestions = []
            return
        }
        let like = "%" + q + "%"
        suggestions = Database.shared.query(
            "SELECT * FROM members WHERE name LIKE ? OR phone LIKE ? ORDER BY created_at DESC LIMIT 8",
            bindings: [.text(like), .text(like)]).map { MemberStore.rowFromDBRow($0) }
    }
}

// MARK: - Member PIN prompt

/// 4-digit member PIN sheet for deduct (Android fix5): wrong PIN shows
/// an error and stays open for retry; cancel aborts the deduct.
struct PinPromptView: View {
    let member: MemberRow
    let onConfirm: (String) -> Bool
    let onCancel: () -> Void

    @State private var pin = ""
    @State private var errorText = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(String(format: L10n.string("rc_pin_title"), member.name))
                    .font(.headline)
                SecureField("", text: $pin)
                    .keyboardType(.numberPad)
                    .font(.title)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: pin) { newValue in
                        let digits = newValue.filter { $0.isNumber && $0.isASCII }
                        let trimmed = String(digits.prefix(4))
                        if trimmed != newValue { pin = trimmed }
                    }
                if !errorText.isEmpty {
                    Text(errorText)
                        .font(.subheadline)
                        .foregroundColor(.red)
                }
                Spacer()
            }
            .padding(16)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common_cancel")) { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("common_confirm")) {
                        if onConfirm(pin) {
                            // Correct PIN: the parent dismisses the sheet.
                        } else {
                            errorText = L10n.string("rc_pin_wrong")
                            pin = ""
                        }
                    }
                    .bold()
                }
            }
        }
    }
}
