#!/usr/bin/env bash
# dup-scan.sh — flavor duplicate scan (leanback ∩ mobile) with L1/L2/L3 口径.
#
# Contract (master plan §2.2.2): the same "TV differs from phone" fact is written
# three times. This scanner reports the source-set duplication half of it.
#
# 口径 are reported separately and MUST NOT be mixed (§2.2.2 warning):
#   L1 byte identical      open(a,'rb').read() == open(b,'rb').read()   -> 11
#   L2 line-set identical  stripped, blanks dropped, as a SET            -> 12
#   L3 jaccard             stripped, blanks + comment lines dropped, deduped
#                          |A∩B| / |A∪B|                                 -> avg 0.584
# Deletion is only safe on L1 (diff -q empty); L3 = 1.000 with L1 != must be
# diff -u reviewed first — that is `QualityAdapter` in batch 1.2.
#
#   bash scripts/arch/dup-scan.sh [--json-out PATH] [--baseline PATH] [--check-namespace]
#
# Without --baseline this is pure reporting (exit 0 unless a flavor source set
# shadows main, which the baseline expectation is 0 for). With --baseline it
# additionally fails on any dup file or namespace file that is NOT in the frozen
# baseline — that is the "只减不增" rule from §6.9.
#
# --check-namespace scopes to app/src/main (production). The 51 same-package test
# classes under app/src/test/java/androidx/... are test scaffolding, not shipped
# application code, and are not part of the C4 debt.
#
# Exit: 0 ok (or no new violation), 1 violation, 2 usage/env, 3 failure.
set -uo pipefail

JSON_OUT=""
BASELINE=""
CHECK_NAMESPACE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json-out) JSON_OUT="${2:-}"; shift 2 ;;
    --json-out=*) JSON_OUT="${1#*=}"; shift ;;
    --baseline) BASELINE="${2:-}"; shift 2 ;;
    --baseline=*) BASELINE="${1#*=}"; shift ;;
    --check-namespace) CHECK_NAMESPACE=1; shift ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: not in a Git worktree" >&2; exit 2; }
cd "$repo_root"

PY=""
for candidate in python python3 py; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys' >/dev/null 2>&1; then
    PY="$candidate"; break
  fi
done
[[ -n "$PY" ]] || { echo "ERROR: no working Python (tried python, python3, py)" >&2; exit 2; }

"$PY" - "$JSON_OUT" "$CHECK_NAMESPACE" "$BASELINE" <<'PYEOF'
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.join("scripts", "arch"))
import _archlib as L

json_out = sys.argv[1] if len(sys.argv) > 1 else ""
check_namespace = sys.argv[2] == "1" if len(sys.argv) > 2 else False
baseline_path = sys.argv[3] if len(sys.argv) > 3 else ""


def git(*args):
    try:
        return subprocess.run(("git",) + args, capture_output=True, text=True,
                              check=False).stdout.strip()
    except OSError:
        return ""


root = os.getcwd()
lb_base, mb_base, dup_paths = L.flavor_dup_map(root)

rows = []
byte_identical, line_set_identical = [], []
buckets = {"1.000": 0, "0.95-1.0": 0, "0.90-0.95": 0, "0.85-0.90": 0,
           "0.70-0.85": 0, "0.50-0.70": 0, "<0.50": 0}
total_lines = 0
jaccard_sum = 0.0

for name in dup_paths:
    left_path = os.path.join(root, lb_base, name)
    right_path = os.path.join(root, mb_base, name)
    with open(left_path, "rb") as handle:
        left_raw = handle.read()
    with open(right_path, "rb") as handle:
        right_raw = handle.read()
    left_text = left_raw.decode("utf-8", "ignore")
    right_text = right_raw.decode("utf-8", "ignore")

    left_lines = left_raw.count(b"\n")
    right_lines = right_raw.count(b"\n")
    total_lines += left_lines + right_lines

    is_byte = left_raw == right_raw
    left_set = {ln.strip() for ln in left_text.splitlines() if ln.strip()}
    right_set = {ln.strip() for ln in right_text.splitlines() if ln.strip()}
    is_line_set = (not is_byte) and left_set == right_set

    value = L.jaccard(L.jaccard_set(left_text), L.jaccard_set(right_text))
    jaccard_sum += value
    bucket = L.jaccard_bucket(value)
    buckets[bucket] += 1

    if is_byte:
        byte_identical.append(name)
    if is_line_set:
        line_set_identical.append(name)

    rows.append({
        "path": name,
        "leanback_lines": left_lines,
        "mobile_lines": right_lines,
        "jaccard": round(value, 4),
        "bucket": bucket,
        "byte_identical": is_byte,
        "line_set_identical": is_line_set,
    })

rows.sort(key=lambda r: (-r["jaccard"], r["path"]))
overrides = L.main_overrides(root)

# 4A/4B/4C are the plan's batch groupings (§4.5.3, §2.2.2).
four_a = sum(1 for r in rows if r["bucket"] in ("1.000", "0.95-1.0", "0.90-0.95"))
four_b = sum(1 for r in rows if r["bucket"] in ("0.85-0.90", "0.70-0.85", "0.50-0.70"))
four_c = sum(1 for r in rows if r["bucket"] == "<0.50")

# C4 rule: no application code under androidx.* / java.* / kotlin.* namespaces.
# Scoped to app/src/main — production only (see header note).
namespace_files = []
ns_root = os.path.join(root, "app", "src", "main")
for path in L.walk_files(ns_root, (".java",)):
    rel_path = L.rel(root, path)
    marker = "/java/"
    if marker not in rel_path:
        continue
    package_path = rel_path.split(marker, 1)[1]
    if package_path.startswith(("androidx/", "java/", "kotlin/")):
        namespace_files.append({"path": rel_path, "lines": L.count_lines(path)})
namespace_files.sort(key=lambda r: r["path"])

report = {
    "schema_version": 1,
    "metric_counter": "jaccard-L3-v1",
    "commit": git("rev-parse", "HEAD"),
    "dup_files": len(rows),
    "dup_lines": total_lines,
    "avg_jaccard": round(jaccard_sum / len(rows), 4) if rows else 0.0,
    "L1_byte_identical": {
        "count": len(byte_identical),
        # Plan §2.2.2 quotes 816 = ONE side; the two-sided total is 1,632. Both are
        # reported so neither number has to be re-derived (and mis-derived) later.
        "lines_one_side": sum(r["leanback_lines"] for r in rows if r["byte_identical"]),
        "lines_both_sides": sum(r["leanback_lines"] + r["mobile_lines"]
                                for r in rows if r["byte_identical"]),
        "files": byte_identical,
    },
    "L2_line_set_identical_extra": {"count": len(line_set_identical), "files": line_set_identical},
    "buckets": buckets,
    "batches": {"4A": four_a, "4B": four_b, "4C": four_c},
    "main_overrides": {k: len(v) for k, v in sorted(overrides.items())},
    "files": rows,
    "namespace": {"count": len(namespace_files), "files": namespace_files},
    # Flat lists consumed by guard.sh / dup-scan --baseline.
    "dup_files_list": sorted(dup_paths),
    "namespace_files_list": [r["path"] for r in namespace_files],
}

text = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
if json_out:
    with open(json_out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    print("wrote %s" % json_out)
print("dup_files=%d dup_lines=%d avg_jaccard=%.4f L1=%d L2extra=%d 4A=%d 4B=%d 4C=%d"
      % (report["dup_files"], report["dup_lines"], report["avg_jaccard"],
         len(byte_identical), len(line_set_identical), four_a, four_b, four_c))

violation = False
for flavor, hits in sorted(overrides.items()):
    if hits:
        print("VIOLATION: %s source set shadows %d main file(s): %s"
              % (flavor, len(hits), ", ".join(hits)), file=sys.stderr)
        violation = True

if check_namespace and namespace_files:
    print("VIOLATION: %d application file(s) still under a third-party namespace:" % len(namespace_files),
          file=sys.stderr)
    for row in namespace_files[:10]:
        print("  %s (%d lines)" % (row["path"], row["lines"]), file=sys.stderr)
    violation = True

# --baseline: dup files / namespace files may only shrink (§6.9 只减不增).
if baseline_path:
    with open(baseline_path, encoding="utf-8") as handle:
        base = json.load(handle)
    base_dups = set(base.get("dup_files_list", []))
    new_dups = sorted(set(dup_paths) - base_dups)
    if new_dups:
        print("VIOLATION: %d flavor duplicate(s) not in baseline:" % len(new_dups), file=sys.stderr)
        for name in new_dups:
            print("  %s" % name, file=sys.stderr)
        violation = True
    base_ns = set(base.get("namespace_files_list", []))
    new_ns = sorted(r["path"] for r in namespace_files if r["path"] not in base_ns)
    if new_ns:
        print("VIOLATION: %d namespace file(s) not in baseline:" % len(new_ns), file=sys.stderr)
        for name in new_ns:
            print("  %s" % name, file=sys.stderr)
        violation = True
    if not (new_dups or new_ns):
        print("OK: no new duplicates or namespace files vs baseline")

if violation:
    sys.exit(1)
PYEOF
rc=$?
if [[ $rc -eq 1 ]]; then exit 1; fi
if [[ $rc -ne 0 ]]; then echo "ERROR: dup-scan measurement failed (rc=$rc)" >&2; exit 3; fi
