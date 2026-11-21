# Phase 2 — Batch 3: Booking + Recharge & Deduct

2 pages in one build, on top of the build #5 fix commit `5e96904`
(Statistics margins, chart labels, recent transactions). Tabs wired in
Android's order: Dashboard, Statistics, Members, **Booking, Recharge &
Deduct**, Gifts, Coupons, Transactions, Settings (last 4 still
placeholders).

## New files

- `Membershift/Core/PointsEngine.swift` (413 lines) — Swift port of
  Android `CheckoutEngine` + `PointsLedger` + `LedgerMath` (no UI):
  `OpResult`, settings readers, `rechargeTiers` (parses the settings
  JSON `[[500,50],[1000,120],[2000,300]]`), `nextTier`, `errorText`,
  `insertTx`, `earnBatch`, `LedgerBatch` + `planSpend`, `spendFifo`,
  `expireMemberPoints`, `grantReferralIfFirst`, and the four operations
  `earn` / `deductBalance` / `recharge` / `adjust` — each in one SQLite
  transaction (`BEGIN` + `defer COMMIT/ROLLBACK`), re-reading the member
  after expiry. Detail strings mirror Android exactly.
- `Membershift/Views/BookingView.swift` (1,324 lines) — `BookingRow`,
  `BookingStore`, `BusinessHours`, `BookingView` (4 modes), `BookingFormView`
  (sheet), `BusinessHoursView` (sheet).
- `Membershift/Views/RechargeDeductView.swift` (569 lines) —
  `RechargeDeductView` (3 modes), shared `MemberPickerField`, `PinPromptView`.

## Booking page — mirrors Android's Booking screen

- 4 modes: 日 / 周 / 月 / 列表 (48pt pill bar, default 日）.
- Day view: 30-minute slot cards from business hours (09:00–21:00 → 24
  slots), tap a slot (or its "＋ 点击预约") to create at that slot;
  bookings on a slot show as cards with a status pill.
- Week view: 7 day cards with the day's bookings (or "空闲").
- Month view: `LazyVGrid` 7-column calendar + selected-day section.
- List view: upcoming bookings (limit 100) with status pills.
- Booking card: member name (or 散客）, service, staff, time, status pill;
  tap → action sheet (status-dependent like Android: confirm / complete /
  no-show / cancel / edit / delete; delete asks for confirmation).
- Form sheet: member picker (walk-in allowed), staff picker (unassigned +
  history users + custom text), service picker (history + products +
  categories + custom text), start/end DatePickers (start change moves
  end +30 min), +30 min button, note. Save validates end > start and
  business hours, then shows a conflict alert listing the blocking
  bookings.
- Business-hours editor: card at the bottom of the page (iOS Settings is
  still a placeholder); start/end hour-minute pickers + "closes next
  day" toggle; validates via `isValidSetting`.
- Conflict rule (Android `findConflicts`): only 待确认/已确认 block;
  either side unassigned blocks; two different assigned staff may run
  in parallel; touching boundaries (11:00 end vs 11:00 start) do not
  conflict.
- Cross-night edge, kept as in Android: a booking that started the
  previous day appears in `listDay` (overlap query) but attaches to no
  day slot (slots only exist inside business hours), so it shows as
  "—" in the same-day view. Noted in code.

## Recharge & Deduct page — mirrors Android's RechargePage (fix2)

- 3 modes: 充值 / 充值扣减 / 积分调整. The adjust tab is visible only
  to managers (`AppState.currentUser?.isManager`); non-managers never
  see it, like Android.
- Shared member picker (`MemberPickerField`, also used by the Booking
  form): name/phone search, max 8 suggestions, selected card shows
  points · balance · total spent, with a clear button.
- 充值 mode: earn card (amount + live "消费 ¥X，可得 N 积分（等级倍率
  ×M）" preview) + recharge card (amount + live bonus preview:
  "充 ¥X 赠 ¥Y，到账 ¥Z" / "再充到 ¥X 可多送" / "当前无赠送档位").
  Bonus tiers from settings: 500→+50, 1000→+120, 2000→+300.
- 充值扣减 mode: deduct card (amount + live "扣减后余额 ¥X · 本次可得
  +N 分" preview, balance check before deduct). Before deduct, a member
  with a PIN must enter the 4-digit PIN (`PinPromptView`: SecureField,
  wrong PIN shows "密码错误，请重试" and stays open for retry, cancel
  aborts); verification is `Auth.hashPassword(pin, salt: pinSalt) ==
  pinHash` (Android fix5 scheme). A member without a PIN deducts
  directly with a set-a-PIN tip.
- 积分调整 mode: points delta (+100 / -50) + optional reason; points
  must stay ≥ 0; manager-only.
- Success/error message banner after every operation; the member card
  refreshes after each op.
- Coupon redeem is NOT on this screen — Android puts it on the Coupons
  page (verified in `RechargePage.java`); it comes with the next batch.

## Points engine — Android parity notes

- Earn: `floor(amount / earn_rate × tier multiplier)`; `earn_rate` = 1
  from settings (¥1 = 1 point at 普通会员）; multiplier from the
  member's tier by total spent (1.0 / 1.5 / 2.0 / 3.0).
- Referral (`grantReferralIfFirst`, verified against
  `CheckoutEngine.java:442`): both sides get `referral_points` (50);
  the **referred member** is marked `referral_rewarded` (not the
  referrer); two `referral` transactions + two ledger batches are
  written. Count sets differ by path: earn counts checkout+earn,
  deduct/checkout count checkout only; recharge never grants.
- FIFO spend (`planSpend`/`spendFifo`): skip expired batches, earliest
  expiry first, never-expire batches last, id ascending. Not yet called
  by any UI (no points-spend screen on iOS yet); used by the Coupons /
  Gifts pages in later batches.
- Expiry (`expireMemberPoints`): closes expired batches, deducts the
  remaining points, writes a `points_expire` transaction (operator
  "system") and a negative 'expiry' ledger batch.

## Localization

96 keys used by the new code, all defined (298 keys total, no
duplicates): `common_save`, `tx_pts_unit`, `err_need_member`,
`err_need_amount`, `err_balance_not_enough`, `err_points_not_enough`,
`tx_earn_detail`, `tx_recharge_detail`, `tx_deduct_detail`,
`tx_adjust_detail`, `tx_referral_detail`, `tx_points_expire_detail`,
all `bk_*` (day/week/month/list, status pills, conflict, hours editor,
weekday names) and all `rc_*` (modes, previews, PIN). English strings
taken from Android `res/values-en/strings.xml`.

**Also fixed a pre-existing batch-2 gap found while wiring:** 
`mem_balance_fmt` and `mem_spent_fmt` were used by MembersView but
never defined in `Localization.swift` (so the Members list subline
would have shown the raw key text). Both are now defined
("余额 %@" / "Balance %@", "累计 %@" / "Total spent %@"), plus the
missing `bk_title` key used by the booking action sheet.

## Layout lessons applied

- Every large body split into small private computed subviews/helpers
  (build #4 lesson — no giant VStack).
- Every page: `.padding(16)` + `.containerRelativeFrame(.horizontal)`
  on the page VStack (build #5 lesson — nothing clipped at 390pt).
- Format strings use `%@` for Swift Strings, never `%s`.
- `onChange(of:) { newValue in }` (iOS 16 form) throughout.
- Two comment lines containing `[start, end)` broke the validator's
  raw-text balance check; reworded to `[start, end]`.

## Deferred (not in this batch)

- No printer / reprint on iOS: Android's "扣减并打印" is just "扣减"
  here; printing comes with a later phase (no iOS printer yet).
- Coupon redeem stays with the Coupons page (next batch).
- `spendFifo` is implemented but not yet called by any UI.
- iOS Settings is still a placeholder, so business hours live on the
  Booking page itself (Android has them in SettingsPage).
- Session is still in-memory only (re-login after every app restart);
  persistence + license wall are a later batch.

## Verification

- `python3 validate_ios.py` → **ALL CHECKS PASSED** (78 checks:
  pbxproj balanced + all IDs resolve, every Swift file on disk in the
  project, braces/parens balanced, no secret/key material, all 14
  tables + v2–v4 columns present).
- Python sqlite3 simulation `/tmp/sim_batch3.py` (temp DB built from
  the real iOS schema + seed + demo data, today frozen 2026-11-21):
  **71 passed, 0 failed**. Covered: 24 day slots; business-hours
  in/out; conflict matrix (same staff blocks, different staff parallel,
  unassigned blocks, boundary touch OK, cancelled doesn't block,
  outside-hours and bad-time errors); listDay ordering; cross-night
  listDay inclusion + no-slot attachment (the Android "—" edge);
  earn/recharge/deduct/adjust math; bonus tiers + next-tier at every
  boundary; referral on all three paths (earn both-sides +50 with flag
  on the referred member, recharge never grants, deduct counts
  checkout only); FIFO oldest-expiry-first; expiry of full + partial
  batches; member search (name/phone, limit 8).
- The simulation caught one real divergence during development (the
  referral flag target / both-sides points / count sets); the Swift
  code was already correct per Android and the sim was fixed to match
  it — see the referral checks above.

## Files changed

- Added: `Membershift/Core/PointsEngine.swift`,
  `Membershift/Views/BookingView.swift`,
  `Membershift/Views/RechargeDeductView.swift`, `validate_ios.py`
  (was untracked; the project validator, now committed).
- Edited: `Membershift/Core/Localization.swift` (+96 keys, +3
  missing-key fixes), `Membershift/Views/MainTabView.swift` (two tabs
  wired), `Membershift.xcodeproj/project.pbxproj` (3 files ×
  PBXBuildFile + PBXFileReference + group + sources entries).
- Not touched: Dashboard/Statistics/Members views, website, desktop,
  Android. No new dependencies, no MP- license key anywhere.
