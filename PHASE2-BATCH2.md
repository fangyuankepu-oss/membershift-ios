# Phase 2 batch 2 — Statistics + Members (2 pages, one build)

Built 2026-11-21. User decided 2 pages per build. Wired into MainTabView
in Android's tab order (Dashboard, Statistics, Members, …); the other
6 tabs stay placeholders.

## Statistics (`Views/StatisticsView.swift`)

Mirrors Android `StatisticsPage` + `Store` range helpers (same SQL,
same date rules):

- Range tabs 今天 / 本周 / 本月 / 近 30 天 / 自定义 (default 近 30 天,
  48pt equal buttons, deep-green selected state, Android fix9).
  Custom shows two compact DatePickers; start/end clamp each other.
- 4 summary cards (2-col grid): 消费总额 / 充值总额 / 新增会员 /
  积分兑换, each with 较上周期 +x.x% vs the previous equal-length
  range (prev == 0 → "0.0%" or "+100.0%", Android `pctText`).
- 5 KPI rows: 订单数 / 活跃会员 / 复购率 / 积分兑换率 / 客单价.
- 消费趋势 self-drawn bar chart (one bar per day in range).
- 时段分布 6 buckets (9–11 … 19–21), 等级分析 (count + spend per
  tier), 支付方式 (localized names, biggest first), 优惠券
  (issued · used · usage rate), 礼品兑换 Top 5 (by transactions ref_id).
- 每日明细 table: tap a header to sort (default date desc, numeric
  columns asc on first tap, Android fix2), 10 rows per page + prev/next.

## Members (`Views/MembersView.swift`)

Mirrors Android `MembersPage` + `Store` member helpers:

- List: search (name / phone), 5 segment tabs with counts
  (全部 / 新客 30d / 沉睡 90d / 高价值 top 20% / 积分将过期),
  tag filter menu, 新增会员 button.
- Row: name, tier badge (DB hex colour), 将过期 badge, subline
  (phone · points · balance · total spent).
- Detail 360° sheet: avatar, tier line (discount + points multiplier),
  tier progress bar, expiring points (30d ledger), visits + avg order,
  gender / birthday / email / PIN status / note, preferred categories
  + products Top 3 (from checkout items JSON), tags (add / delete),
  referrer info + referred count + reward status, coupons held
  (used / expired / unused), recent 8 transactions, Edit / Delete.
- Add/edit form: name, phone, optional email (minimal @ check),
  optional 4-digit PIN (salt + sha256(salt + "::" + pin), Android
  fix5; edit: blank keeps, clear checkbox when set), gender,
  birthday (toggle + picker), searchable referrer picker (green + ✓
  current selection, Android fix11 pattern), note. Validations mirror
  Android: name/phone required, phone unique, email shape, PIN 4 digits.
- Delete (manager only): confirm alert, then the manager password
  must be re-entered (Android fix6; wrong password clears and stays
  open for retry); cascade deletes coupons / ledger / tags and clears
  referrer_id on other members, in one transaction.

## Deferred (not silently dropped)

- 分群发券 (bulk coupon issue to a segment) — needs the Coupons page.
- 打印积分记录 (print member record) — no printer on iOS yet.

## Verification (2026-11-21, no Swift compiler in VM)

- `/tmp/validate_ios.py` (recreated after the /tmp loss; fixes:
  pbxproj root-group ID without comment, codemagic `instance_type`,
  bundle ID via `$(PRODUCT_BUNDLE_IDENTIFIER)`): **ALL CHECKS PASSED**
  (54 objects, 16 Swift files, all referenced IDs resolve).
- Python sqlite3 simulation (`/tmp/sim_batch2.py`): temp DB built
  from the real iOS schema + seed + demo data, today frozen
  2026-11-21. All expected values match the Swift queries:
  - Stats (30d): sales $744 (+100.0%), recharge $500, new 3,
    redeemed 0, orders 3, active 3, repeat 0%, redeem 0%, avg $248;
    daily 11-18 $320 / 11-20 $156 / 11-21 $268; hours 11–13 $156,
    13–15 $268, 17–19 $320; tiers 普通会员 3人 · $744; pays
    支付宝 $320 / 现金 $268 / 微信 $156; coupons 0/0; gifts none;
    daily 11-21 (new 0, sales 268, recharge 500, issued 268,
    redeemed 0, active 2).
  - Members order 王小明 / 李小红 / 张大强; segments new {1,2,3},
    dormant {}, vip {3} (threshold $320), expiring {2}; 李小红
    120 pts expiring 2026-12-21, referrer 王小明, 1 visit,
    pref 卤味 $156, 2 txs; phone-dup check, PIN set/verify
    (sha256(salt + "::" + 1234)), delete cascade (2 members left,
    0 ledger rows for the deleted member).

## Notes

- Format strings use `%@` for Swift Strings (`%s` is unsafe in
  `String(format:)`); `%d` args are cast to `Int` (Dashboard pattern).
- No MP- key anywhere; no new dependencies; nothing outside the iOS
  project was touched. Next batch: Booking + Recharge & Deduct.
