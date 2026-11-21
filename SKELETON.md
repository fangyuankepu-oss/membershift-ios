# Membershift iOS — Skeleton (Phase 1)

Date: 2026-11-21. Status: skeleton only — it compiles in principle, but has
never been built (no Mac / Xcode in this VM). Nothing has been pushed to
GitHub; Codemagic is not connected yet.

Decision behind this build (user, 2026-11-21 01:02 EST): route A — Swift
native + Codemagic free build (500 min/month, build-time only). Codemagic
builds an UNSIGNED .ipa; the user installs it via AltStore with a free
Apple ID (7-day certificate, re-sign weekly) and applies for the Apple
Developer account ($99/yr) later, then TestFlight / App Store. Expo
(route B) was rejected by implication — it would force rewriting the
finished native Android app.

## What was built

- Swift + SwiftUI, zero external dependencies (no SPM packages — the
  Codemagic build fetches nothing).
- Bundle ID `com.membershift.app`, version 1.3.0 (build 1), iOS 16+ target,
  iPhone + iPad.
- App entry + login screen: `admin / 123456`, same password-hash scheme as
  Android (`sha256(salt + "::" + password)`, UTF-8; Latin-1 legacy hash
  auto-upgrades on login — see `Core/Auth.swift`).
- Thin SQLite wrapper over system `libsqlite3` (linked `libsqlite3.tbd`,
  `import SQLite3` — no third-party lib). Creates all tables on first
  launch and seeds the Android defaults. Demo-data loader is a stub.
- Navigation shell with the same 9 tabs as Android, same order:
  Dashboard, Statistics, Members, Booking, Recharge & Deduct, Gifts,
  Coupons, Transactions, Settings. Each page is a clearly-marked
  placeholder view for now.
- Brand: deep green `#145a47`, bright green `#22C55E`, gold `#c9a227`;
  app icon is a deep-green rounded square with a white M (generated,
  11 sizes in the asset catalog).
- Languages: Simplified Chinese (default) + English only. Android ships
  7; the other 5 are a phase-2 addition (only `Core/Localization.swift`
  needs new columns).
- `codemagic.yaml`: workflow `ios-unsigned` — macOS `mac_mini_m2`,
  Xcode 26.2 (Codemagic default, verified 2026-11-21), builds with
  `CODE_SIGNING_ALLOWED=NO`, packages the `.app` into
  `Membershift-unsigned.ipa`, exports it as a build artifact.
  No signing, no Apple credentials anywhere.

## File tree

```
member-app-ios/
├── codemagic.yaml                  # Codemagic workflow (repo root)
├── SKELETON.md                     # this file
├── Membershift/
│   ├── MembershiftApp.swift        # @main: open DB -> login -> 9-tab shell
│   ├── Info.plist
│   ├── Assets.xcassets/            # AppIcon (11 sizes) + AccentColor #145a47
│   ├── Core/
│   │   ├── Database.swift          # libsqlite3 wrapper, schema, seed
│   │   ├── Auth.swift              # SHA-256 login, legacy-hash upgrade
│   │   ├── License.swift           # trial status + STUB verifier (no key)
│   │   ├── DemoData.swift          # demo-data loader STUB
│   │   ├── Localization.swift      # zh-Hans + en string table
│   │   └── Theme.swift             # brand colours
│   └── Views/
│       ├── AppState.swift          # session (in-memory) + language
│       ├── LoginView.swift         # login screen
│       ├── MainTabView.swift       # 9-tab shell
│       ├── PlaceholderPage.swift   # placeholder page + DB error view
│       └── LicenseWallView.swift   # trial/activation wall (not wired)
└── Membershift.xcodeproj/
    ├── project.pbxproj             # hand-authored (generator: /tmp/gen_ios_project.py)
    └── xcshareddata/xcschemes/Membershift.xcscheme   # shared scheme
```

## Schema mapping (Android DbHelper DB_VERSION 4 -> iOS)

Ported 1:1 — same table/column names, types, defaults, and seed data.
File name is the same: `member_system.db` (iOS: Application Support
directory; Android: internal database directory).

- Tables (14, not 12): `users`, `tiers`, `members`, `gifts`, `coupons`,
  `member_coupons`, `transactions`, `products`, `points_ledger`,
  `member_tags`, `bookings`, `settings`, `license`, `seq`.
  Note: Android FINAL.md says "12 tables" but `DbHelper` actually
  creates 14 (10 collections + bookings + settings + license + seq);
  all 14 are ported.
- v2–v4 columns included: `transactions.ref_id`, `transactions.pay_method`,
  `members.email`, `members.pin_salt`, `members.pin_hash`.
- JSON-array columns (`perms`, `categories`, `product_ids`, `items`) stay
  TEXT holding JSON strings, exactly as on Android.
- Seed defaults (same as Android): admin user (salted SHA-256 of
  `123456`); 4 tiers (普通 0 / 银卡 5000 / 金卡 20000 / 钻石 50000);
  3 gifts (水杯 500 / 雨伞 800 / 50元代金券 2000); settings incl.
  `redeem_rate=20`, `referral_points=50`, `min_redeem_points=100`,
  `points_expiry_months=12`, `recharge_tiers=[[500,50],[1000,120],[2000,300]]`,
  `auto_print_exchange=1`, `auto_print_adjust=0`; license
  `installed_at` = install date; seq counters (`user`=2, `tier`=5,
  `gift`=4, rest 1).
- Trial: 14 days from `installed_at` (same as Android native / desktop).
- Differences from Android, by design: no `onUpgrade` migration path
  (fresh DB only — no iOS users exist yet); no auto-backup hook;
  `nextId` mirrors Android's `seq` contract.

## Android behaviours intentionally NOT in the skeleton

- Checkout is off the nav on Android too (`inNav=false`); not a tab here.
  "Earn points" (消费兑换积分) is a section inside the Recharge page on
  Android, not its own tab — same here.
- Permission-based tab hiding (14 permission keys; manager sees all) —
  phase 2; the skeleton shows all 9 tabs.
- License wall is a placeholder view and is NOT wired as a launch gate.
- Demo data is a stub (`DemoData.loadIfNeeded` returns false); the
  Android content to port is documented in the file.
- Session is in-memory only (Android persists `ms_session`); re-login is
  required after every app restart until phase 2 persists it.
- No printing, no backup/restore, no migration import (no iOS legacy
  data exists), no receipt templates.

## Security notes

- No MP- activation-code signing key anywhere in this project. `License.swift`
  contains only a stub verifier interface that always fails verification;
  the Android generator secret stays seller-only and was not copied.
- No Apple credentials, certificates, provisioning profiles, or API keys
  in the repo. The Codemagic workflow needs none of them.
- Member PINs (`pin_salt` / `pin_hash`) are ported as columns only; no
  PIN UI or verification exists yet.

## Verification done locally (2026-11-21)

No Swift compiler exists in this VM, so the code could NOT be compiled
here. What was checked instead (script `/tmp/validate_ios.py`,
all passed):

- `project.pbxproj`: braces/parens balanced; 47 objects defined, all
  referenced IDs resolve (0 missing); every referenced file exists;
  all 12 Swift files on disk are in the project; required settings
  present (bundle ID, iOS 16.0, 1.3.0, Swift 5.0, libsqlite3.tbd,
  Info.plist path).
- `codemagic.yaml`: parses as YAML; workflow `ios-unsigned`,
  `mac_mini_m2`, Xcode 26.2, `CODE_SIGNING_ALLOWED=NO` present,
  artifact `Membershift-unsigned.ipa` declared.
- `Membershift.xcscheme`: parses as XML; its target ID matches the
  pbxproj target.
- `Info.plist`: parses (plistlib). Asset catalog JSONs parse; all 11
  icon files exist; icon visually checked (deep-green square, white M).
- Swift files: braces/parens balanced per file; no secret/key material
  (no `MP1-`, no signing-key names, no long hex constants).
- Schema: all 14 tables and the v2–v4 columns present in the iOS port.

## Known compile risks (must be confirmed by the first Codemagic build)

1. **project.pbxproj is hand-authored** — structure follows the canonical
   Xcode 16 format and passed the checks above, but only a real
   `xcodebuild` run proves it. Most likely failure points, in order:
   (a) a missing/misspelled build-setting key, (b) the shared scheme
   not being picked up, (c) `import SQLite3` needing an extra step
   (it normally works once `libsqlite3.tbd` is linked, which it is).
2. **Swift source was not compiled.** Care was taken (iOS 16 API forms
   only: one-parameter `onChange`, `.toolbar(.hidden, for:)`,
   `NavigationStack`, shorthand `if let`); the riskiest spots are the
   C-interop calls in `Database.swift` (`sqlite3_bind_text` with
   `SQLITE_TRANSIENT`, `withMemoryRebound` in `columnText`) and the
   `guard … let stmt else` shadowing pattern. If the build fails, the
   Codemagic log will name the file/line — fix there, do not rewrite
   the project.
3. **Xcode 26.2 pinned in codemagic.yaml.** If Codemagic retires 26.2,
   change one line to `26.3` (or `latest`).
4. **Unsigned .ipa + AltStore**: the build produces an unsigned app;
   AltStore re-signs with a free Apple ID (7-day cert). AltStore
   requires the .ipa's bundle ID to be unique to the user's Apple ID —
   first install may need the bundle ID changed in Xcode settings if
   it collides (unlikely for `com.membershift.app`).

## Codemagic setup — steps the user still needs

(Do NOT do these for the user; they need the user's GitHub account.)

1. **Push this folder to GitHub.** Suggested: new repo
   `fangyuankepu-oss/membershift-ios` (public, like `membershift`),
   or a subfolder of the existing repo — but note `codemagic.yaml`
   must sit at the repository root, so a separate repo is cleaner.
   Push the whole `member-app-ios/` contents so that `codemagic.yaml`
   and `Membershift.xcodeproj/` are at the repo root.
   Nothing has been pushed yet.
2. **Create a Codemagic account** at codemagic.io — sign in with GitHub
   (free tier, no card). Connect the GitHub account so Codemagic can
   read the repo.
3. **Add the app in Codemagic**: pick the repo. Codemagic detects
   `codemagic.yaml` at the root automatically — choose the
   **"Use codemagic.yaml"** configuration (not the Workflow Editor),
   workflow **`ios-unsigned`**, branch `main`.
4. **Start the first build** (Start new build → branch `main` →
   workflow `ios-unsigned`). Watch the log: expected result is a green
   build with artifact `Membershift-unsigned.ipa`.
5. **Download the .ipa** from the build's Artifacts tab.
6. **Install with AltStore** (free Apple ID): install AltServer on
   Windows, connect the iPhone, install AltStore on the phone, then
   open the .ipa in AltStore (Files app → share → AltStore). The app
   certificate lasts 7 days; AltStore re-signs automatically over Wi-Fi
   when the phone and the PC are on the same network (AltServer must be
   running). If it expires, re-install the same .ipa.
7. **First-run check on the phone**: app opens to the login screen →
   log in with `admin / 123456` → 9 tabs appear, each showing its
   "开发中" placeholder. That is the whole phase-1 acceptance test.

## Later (NOT part of this phase)

- Developer account ($99/yr) → re-sign via Codemagic code signing →
  TestFlight / App Store. Also needs a privacy-policy URL — the website
  has no privacy page yet; add one before submission.
- Phase 2 (after the skeleton build goes green): replace placeholder
  pages one by one (Dashboard first), port DemoData, persist the
  session, wire the license wall once the verification scheme is decided.
