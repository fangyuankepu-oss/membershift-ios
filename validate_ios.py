#!/usr/bin/env python3
"""Structural validator for the Membershift iOS project.

No Swift compiler exists in this VM, so this checks everything that
can be checked without one (recreated 2026-11-21; the original lived
in /tmp and was lost on a VM restart):

- project.pbxproj: braces/parens balanced; every referenced object ID
  resolves; every referenced file exists on disk; every Swift file on
  disk is in the project; required settings present (bundle ID,
  iOS 16.0, version 1.3.0, Swift 5.0, libsqlite3.tbd, Info.plist path).
- codemagic.yaml: parses as YAML; workflow ios-unsigned, mac_mini_m2,
  Xcode 26.2, CODE_SIGNING_ALLOWED=NO, artifact Membershift-unsigned.ipa.
- Membershift.xcscheme: parses as XML; its target ID matches pbxproj.
- Info.plist: parses (plistlib). Asset catalog JSONs parse; icon files exist.
- Swift files: braces/parens balanced per file; no secret/key material
  (no MP1-, no signing-key names, no long hex constants).
- Schema: all 14 tables and the v2-v4 columns present in Database.swift.

Exit 0 + "ALL CHECKS PASSED" on success, else exit 1 with failures.
"""
import plistlib
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path.home() / "workspace" / "member-app-ios"
PROJ = ROOT / "Membershift.xcodeproj" / "project.pbxproj"
failures = []


def check(cond, msg):
    print(("PASS " if cond else "FAIL ") + msg)
    if not cond:
        failures.append(msg)


def balanced(text, name):
    depth_b = depth_p = 0
    for ch in text:
        if ch == "{":
            depth_b += 1
        elif ch == "}":
            depth_b -= 1
        elif ch == "(":
            depth_p += 1
        elif ch == ")":
            depth_p -= 1
        if depth_b < 0 or depth_p < 0:
            return False
    return depth_b == 0 and depth_p == 0


# ---- project.pbxproj ----
pbx = PROJ.read_text()
check(balanced(pbx, "pbxproj"), "pbxproj braces/parens balanced")
obj_ids = set(re.findall(r"([0-9A-F]{24})(?:\s*/\*[^*]*\*/)?\s*=\s*\{", pbx))
refs = set(re.findall(r"\b([0-9A-F]{24})\b", pbx))
missing = sorted(refs - obj_ids)
check(not missing, f"pbxproj all referenced IDs resolve ({len(obj_ids)} objects, 0 missing)")
check(len(obj_ids) >= 50, f"pbxproj has {len(obj_ids)} objects")

# every referenced file exists on disk
file_refs = re.findall(
    r"isa = PBXFileReference;[^;]*path = ([^;]+);", pbx)
missing_files = []
for p in file_refs:
    p = p.strip().strip('"')
    if p in ("Membershift.app",):
        continue
    candidates = [ROOT / "Membershift" / p, ROOT / p,
                  ROOT / "Membershift.xcodeproj" / p]
    if not any(c.exists() for c in candidates):
        missing_files.append(p)
check(not missing_files, f"pbxproj referenced files exist ({missing_files or 'all present'})")

# every Swift file on disk is in the project
swift_on_disk = sorted(p.name for p in (ROOT / "Membershift").rglob("*.swift"))
swift_in_proj = sorted(set(re.findall(r"path = (\S+\.swift);", pbx)))
check(swift_on_disk == swift_in_proj,
      f"all {len(swift_on_disk)} Swift files on disk are in the project")
for required in ["com.membershift.app", "IPHONEOS_DEPLOYMENT_TARGET = 16.0",
                 "MARKETING_VERSION = 1.3.0", "SWIFT_VERSION = 5.0",
                 "libsqlite3.tbd", "INFOPLIST_FILE"]:
    check(required in pbx, f"pbxproj setting present: {required}")

# ---- codemagic.yaml ----
try:
    import yaml
    cm = yaml.safe_load((ROOT / "codemagic.yaml").read_text())
    wf = cm["workflows"]["ios-unsigned"]
    check(wf["instance_type"] == "mac_mini_m2", "codemagic instance mac_mini_m2")
    check(str(wf["environment"]["xcode"]) == "26.2", "codemagic Xcode 26.2")
    scripts = " ".join(s.get("script", "") for s in wf.get("scripts", []))
    check("CODE_SIGNING_ALLOWED=NO" in scripts, "codemagic CODE_SIGNING_ALLOWED=NO")
    artifacts = " ".join(wf.get("artifacts", []))
    check("Membershift-unsigned.ipa" in artifacts, "codemagic artifact Membershift-unsigned.ipa")
except ImportError:
    raw = (ROOT / "codemagic.yaml").read_text()
    check("mac_mini_m2" in raw and "26.2" in raw
          and "CODE_SIGNING_ALLOWED=NO" in raw
          and "Membershift-unsigned.ipa" in raw,
          "codemagic.yaml contents (PyYAML unavailable, raw text check)")
except Exception as e:
    check(False, f"codemagic.yaml parses: {e}")

# ---- scheme ----
scheme_dir = ROOT / "Membershift.xcodeproj" / "xcshareddata" / "xcschemes"
schemes = list(scheme_dir.glob("*.xcscheme")) if scheme_dir.exists() else []
check(bool(schemes), "shared scheme exists")
for s in schemes:
    try:
        tree = ET.parse(s)
        refs = tree.getroot().findall(".//BuildableReference")
        target_ids = {r.get("BlueprintIdentifier") for r in refs}
        check(bool(target_ids & obj_ids), f"scheme {s.name} target ID matches pbxproj")
    except Exception as e:
        check(False, f"scheme {s.name} parses as XML: {e}")

# ---- Info.plist ----
try:
    plist = plistlib.loads((ROOT / "Membershift" / "Info.plist").read_bytes())
    bid = plist.get("CFBundleIdentifier")
    check(bid == "com.membershift.app"
          or (bid == "$(PRODUCT_BUNDLE_IDENTIFIER)"
              and "PRODUCT_BUNDLE_IDENTIFIER = com.membershift.app" in pbx),
          "Info.plist bundle ID com.membershift.app (via pbxproj)")
    check("UILaunchScreen" in plist, "Info.plist has UILaunchScreen")
except Exception as e:
    check(False, f"Info.plist parses: {e}")

# ---- asset catalog ----
import json
xcassets = ROOT / "Membershift" / "Assets.xcassets"
if xcassets.exists():
    bad = []
    for jf in xcassets.rglob("Contents.json"):
        try:
            json.loads(jf.read_text())
        except Exception:
            bad.append(str(jf))
    check(not bad, "asset catalog JSONs parse")
    icons = list(xcassets.rglob("*.png"))
    check(len(icons) >= 11, f"asset catalog has {len(icons)} icon files (>= 11)")

# ---- Swift files ----
secret_pat = re.compile(r"MP1-|MP-[A-Z0-9]{4,}|[0-9a-f]{64}|PRIVATE KEY|api[_-]?key\s*=\s*\"[^\"]{8,}\"", re.I)
for f in sorted((ROOT / "Membershift").rglob("*.swift")):
    text = f.read_text()
    check(balanced(text, f.name), f"{f.name} braces/parens balanced")
    check(not secret_pat.search(text), f"{f.name} no secret/key material")

# ---- schema ----
db = (ROOT / "Membershift" / "Core" / "Database.swift").read_text()
tables = ["users", "tiers", "members", "gifts", "coupons", "member_coupons",
          "transactions", "products", "points_ledger", "member_tags",
          "bookings", "settings", "license", "seq"]
for t in tables:
    check(f'CREATE TABLE IF NOT EXISTS {t} (' in db, f"schema table {t}")
for col in ["ref_id", "pay_method", "email", "pin_salt", "pin_hash"]:
    check(col in db, f"schema column {col}")

print()
if failures:
    print(f"FAILED: {len(failures)} check(s)")
    sys.exit(1)
print("ALL CHECKS PASSED")
