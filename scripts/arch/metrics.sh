#!/usr/bin/env bash
# metrics.sh — structural metrics for the WebHTV refactor gate.
#
# Contract (master plan §6.2): stable-order JSON on stdout (or --json-out), and
# byte-identical output across runs on the same tree so baseline diffs are
# meaningful. No Gradle, no JVM, no network. Budget: <20 s.
#
#   bash scripts/arch/metrics.sh [--json-out PATH]
#
# Exit: 0 ok, 2 usage/environment problem, 3 measurement failure.
set -uo pipefail

JSON_OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json-out) JSON_OUT="${2:-}"; shift 2 ;;
    --json-out=*) JSON_OUT="${1#*=}"; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: not in a Git worktree" >&2; exit 2; }
cd "$repo_root"

# python3 is a broken WindowsApps stub in this environment (exit 49, no stdout):
# it resolves on PATH but never runs. Probe each candidate for real execution.
PY=""
for candidate in python python3 py; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys' >/dev/null 2>&1; then
    PY="$candidate"; break
  fi
done
[[ -n "$PY" ]] || { echo "ERROR: no working Python (tried python, python3, py)" >&2; exit 2; }

"$PY" - "$JSON_OUT" <<'PYEOF'
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.join("scripts", "arch"))
import _archlib as L

json_out = sys.argv[1] if len(sys.argv) > 1 else ""


def git(*args):
    try:
        return subprocess.run(("git",) + args, capture_output=True, text=True,
                              check=False).stdout.strip()
    except OSError:
        return ""


root = os.getcwd()
rows = L.java_file_metrics(root)

# ------------------------------------------------------------------ totals
java_files = len(rows)
java_lines = sum(r["lines"] for r in rows)

xml_files = xml_lines = 0
for path in L.walk_files(os.path.join(root, "app", "src"), (".xml",)):
    xml_files += 1
    xml_lines += L.count_lines(path)

# ------------------------------------------------------------ distribution
over = {"over_1000": 0, "over_2000": 0, "over_3000": 0}
for row in rows:
    if row["lines"] >= 1000: over["over_1000"] += 1
    if row["lines"] >= 2000: over["over_2000"] += 1
    if row["lines"] >= 3000: over["over_3000"] += 1

by_lines = sorted(rows, key=lambda r: (-r["lines"], r["path"]))
by_methods = sorted(rows, key=lambda r: (-r["methods"], r["path"]))
by_fields = sorted(rows, key=lambda r: (-r["fields"], r["path"]))

# -------------------------------------------------- packages (main only)
# Plan §7 reports package size for production code only (player 93,238), so test
# source sets must be excluded here or "max package" becomes meaningless.
MAIN = "app/src/main/java/"
pkg = {}
for row in rows:
    if not row["path"].startswith(MAIN):
        continue
    entry = pkg.setdefault(row["package"], {"files": 0, "lines": 0})
    entry["files"] += 1
    entry["lines"] += row["lines"]
packages = [dict(name=k, files=v["files"], lines=v["lines"]) for k, v in pkg.items()]
packages.sort(key=lambda p: (-p["lines"], p["name"]))
top_pkg = packages[0] if packages else {"name": "", "lines": 0, "files": 0}

# Max direct class count in one directory (§2.3 "包内直接类数", expected 90 player/exo).
direct = {}
for path in L.walk_files(root, (".java",)):
    rel_dir = os.path.dirname(L.rel(root, path))
    direct[rel_dir] = direct.get(rel_dir, 0) + 1
max_dir = max(direct.items(), key=lambda kv: (kv[1], kv[0])) if direct else ("", 0)

# ---------------------------------------------------------------- flavors
lb_base, mb_base, dup_paths = L.flavor_dup_map(root)
dup_lines = 0
jaccard_total = 0.0
byte_identical, line_set_identical = [], []
buckets = {"1.000": 0, "0.95-1.0": 0, "0.90-0.95": 0, "0.85-0.90": 0,
           "0.70-0.85": 0, "0.50-0.70": 0, "<0.50": 0}
for name in dup_paths:
    with open(os.path.join(root, lb_base, name), "rb") as handle:
        left_raw = handle.read()
    with open(os.path.join(root, mb_base, name), "rb") as handle:
        right_raw = handle.read()
    dup_lines += left_raw.count(b"\n") + right_raw.count(b"\n")
    if left_raw == right_raw:
        byte_identical.append(name)
    else:
        la = {ln.strip() for ln in left_raw.decode("utf-8", "ignore").splitlines() if ln.strip()}
        lb = {ln.strip() for ln in right_raw.decode("utf-8", "ignore").splitlines() if ln.strip()}
        if la == lb:
            line_set_identical.append(name)
    value = L.jaccard(L.jaccard_set(left_raw.decode("utf-8", "ignore")),
                      L.jaccard_set(right_raw.decode("utf-8", "ignore")))
    buckets[L.jaccard_bucket(value)] += 1
    jaccard_total += value

overrides = L.main_overrides(root)
dup_count = len(dup_paths)

# --------------------------------------------------------------- offenders
# isLeanback — TWO numbers, both reported, never mixed:
#
#   isLeanback_raw_lines      plan §2.2.4 口径: `grep -rn "isLeanback()" | wc -l`
#                             -> 232 at anchor 91cdb8c (reproduced exactly).
#                             It counts MATCHING LINES and therefore also counts
#                             Javadoc/comment mentions. Batch 4.2 added 5 such
#                             mentions while documenting the new policy, so this
#                             number legitimately reads 237 on HEAD even though no
#                             call site changed. Do NOT gate on it.
#
#   isLeanback_callsites      the gate metric: comments stripped, method
#                             DECLARATIONS excluded, matching lines counted.
#                             -> 219 at BOTH 91cdb8c and HEAD, which is the proof
#                             that 4.2 was behaviour-neutral. This is the number
#                             §4.8.6 / batch 4.3 must drive to 0.
is_leanback_raw = 0
is_leanback_prod = 0
is_leanback_test = 0
is_leanback_real = 0
is_leanback_files = set()
setting_calls = 0
setting_files, setting_use_files = set(), set()
app_get_files, player_manager_files = set(), set()
history_files, eventbus_files, namespace_files = set(), set(), set()

for row in rows:
    name = row["set"]
    path = os.path.join(root, row["path"])
    text = L.read_text(path)

    if name in L.PROD_SETS or name in L.TEST_SETS:
        hits = sum(1 for line in text.splitlines() if "isLeanback()" in line)
        is_leanback_raw += hits
        if name in L.PROD_SETS:
            is_leanback_prod += hits
        else:
            is_leanback_test += hits
        if hits:
            for line in L.code_only(text).splitlines():
                if "isLeanback()" in line and not L.ISLEANBACK_DECL_RX.search(line):
                    is_leanback_real += 1
                    is_leanback_files.add(row["path"])

    if row["path"].startswith(MAIN):
        setting_calls += len(L.SETTING_MEMBER_RX.findall(text))
        if L.SETTING_REF_RX.search(text):
            setting_files.add(row["path"])
        if L.SETTING_USE_RX.search(text):
            setting_use_files.add(row["path"])
        if L.APP_GET_RX.search(text): app_get_files.add(row["path"])
        if L.PLAYER_MANAGER_RX.search(text): player_manager_files.add(row["path"])
        if L.HISTORY_RX.search(text): history_files.add(row["path"])
        if L.EVENTBUS_RX.search(text): eventbus_files.add(row["path"])
        if row["path"].startswith(L.MPV_NS_PREFIX + "/"): namespace_files.add(row["path"])

# ------------------------------------------------------------------- tests
# C11 source-text locks: 5-pattern口径, 218 classes / 1,661 cases / 44,150 lines.
lock_classes = lock_tests = lock_lines = 0
lock_by_set = {}
for name in ("test", "testMobile", "testLeanback"):
    base = os.path.join(root, "app", "src", name)
    if not os.path.isdir(base):
        continue
    count = 0
    for path in L.walk_files(base, (".java",)):
        text = L.read_text(path)
        if not L.SOURCE_TEXT_RX.search(text):
            continue
        count += 1
        lock_tests += text.count("@Test")
        lock_lines += text.count("\n")
    lock_by_set[name] = count
    lock_classes += count

# Max methods / fields on the single worst file, plus the plan's headline object
# (TmdbDetailActivity: 1,063 methods / 230 fields) so §4 can be checked directly.
tmdb = [r for r in rows if r["path"].endswith("ui/activity/TmdbDetailActivity.java")]
tmdb = tmdb[0] if tmdb else {"lines": 0, "methods": 0, "fields": 0, "path": ""}

source_sets = {}
for row in rows:
    entry = source_sets.setdefault(row["set"], {"files": 0, "lines": 0})
    entry["files"] += 1
    entry["lines"] += row["lines"]

report = {
    "schema_version": 1,
    "metric_counter": "regex-v1",
    "commit": git("rev-parse", "HEAD"),
    "branch": git("rev-parse", "--abbrev-ref", "HEAD"),
    "totals": {
        "java_files": java_files,
        "java_lines": java_lines,
        "xml_files_app_src": xml_files,
        "xml_lines_app_src": xml_lines,
    },
    "distribution": over,
    "extremes": {
        "max_file_lines": by_lines[0]["lines"] if by_lines else 0,
        "max_file": by_lines[0]["path"] if by_lines else "",
        "max_methods": by_methods[0]["methods"] if by_methods else 0,
        "max_methods_file": by_methods[0]["path"] if by_methods else "",
        "max_fields": by_fields[0]["fields"] if by_fields else 0,
        "max_fields_file": by_fields[0]["path"] if by_fields else "",
        "max_package_lines": top_pkg["lines"],
        "max_package": top_pkg["name"],
        "max_direct_classes": max_dir[1],
        "max_direct_classes_dir": max_dir[0],
        "tmdb_detail_lines": tmdb["lines"],
        "tmdb_detail_methods": tmdb["methods"],
        "tmdb_detail_fields": tmdb["fields"],
    },
    "packages": packages,
    # Per-file list for the ≥1,000-line debt whitelist (guard.sh needs path -> lines
    # to enforce "each frozen file may only shrink", not just the aggregate count).
    "large_files": [
        {"path": r["path"], "lines": r["lines"]}
        for r in by_lines if r["lines"] >= 1000
    ],
    "flavor": {
        "dup_files": dup_count,
        "dup_lines": dup_lines,
        "avg_jaccard": round(jaccard_total / dup_count, 4) if dup_count else 0.0,
        "buckets": buckets,
        "byte_identical": sorted(byte_identical),
        "line_set_identical": sorted(line_set_identical),
        "main_overrides": {k: len(v) for k, v in sorted(overrides.items())},
    },
    "offenders": {
        "isLeanback_callsites": is_leanback_real,
        "isLeanback_raw_lines": is_leanback_raw,
        "isLeanback_prod_raw": is_leanback_prod,
        "isLeanback_test_raw": is_leanback_test,
        "isLeanback_files": len(is_leanback_files),
        "setting_static_callsites": setting_calls,
        "setting_static_files": len(setting_files),
        "setting_static_use_files": len(setting_use_files),
        "app_get_files": len(app_get_files),
        "player_manager_files": len(player_manager_files),
        "bean_history_files": len(history_files),
        "eventbus_files": len(eventbus_files),
        "androidx_namespace_files": len(namespace_files),
    },
    "tests": {
        "source_text_locks": lock_classes,
        "source_text_lock_cases": lock_tests,
        "source_text_lock_lines": lock_lines,
        "source_text_locks_by_set": lock_by_set,
    },
    "source_sets": {k: source_sets[k] for k in sorted(source_sets)},
}

text = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
if json_out:
    with open(json_out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    print("wrote %s" % json_out)
else:
    sys.stdout.write(text)
PYEOF
rc=$?
if [[ $rc -ne 0 ]]; then echo "ERROR: metrics measurement failed (rc=$rc)" >&2; exit 3; fi
