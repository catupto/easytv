#!/usr/bin/env bash
# source-text-tests.sh — classify the 218 C11 source-text assertion test classes.
#
# Why this exists (master plan §2.9 / §5 batch 1.4): 218 test classes (44,150 lines,
# 1,661 cases) assert against the TEXT of .java files instead of behaviour. They are
# why the previous refactor roadmap could not move: every method extraction turns
# them red regardless of whether behaviour changed. Before stage 2/3 touches a
# production file, the tests locking it must be classified and handled.
#
# Classification (plan §2.9.4):
#   A 可迁行为    asserts what is called / in what order / with what result
#                 -> migrate to behaviour assertions on the extracted POJO/interface
#   B 应变契约    asserts an invariant or structural constraint
#                 -> convert to a type/interface assertion (ArchUnit or compile-time)
#   C 无法迁移    asserts "this literal text must exist" with no behavioural meaning
#                 -> delete, and record in an ADR which protection was given up
#
# Heuristics (documented so the ledger can be defended, not guessed):
#   A  the file asserts on captured arguments, call order, counts of invocations, or
#      on values produced by running code (assertThat/assertEquals on runtime objects)
#   C  the file ONLY does substring/indexOf/regex matching against file text
#   B  everything else: mixed, or a declared contract/invariant on structure
#
#   bash scripts/arch/source-text-tests.sh [--json-out PATH] [--summary]
#
# Exit: 0 ok, 2 usage/env, 3 failure.
set -uo pipefail

JSON_OUT=""
SUMMARY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json-out) JSON_OUT="${2:-}"; shift 2 ;;
    --json-out=*) JSON_OUT="${1#*=}"; shift ;;
    --list) SUMMARY=1; shift ;;
    --summary) SUMMARY=1; shift ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
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

"$PY" - "$JSON_OUT" "$SUMMARY" <<'PYEOF'
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.join("scripts", "arch"))
import _archlib as L

json_out = sys.argv[1] if len(sys.argv) > 1 else ""
summary_only = sys.argv[2] == "1" if len(sys.argv) > 2 else False


def git(*args):
    try:
        return subprocess.run(("git",) + args, capture_output=True, text=True,
                              check=False).stdout.strip()
    except OSError:
        return ""


root = os.getcwd()
TEST_SETS = ("test", "testMobile", "testLeanback")

# Signals that a class asserts on runtime behaviour rather than file text.
BEHAVIOUR_SIGNALS = [
    r"\bverify\(", r"\bArgumentCaptor\b", r"\binOrder\(", r"\btimes\(",
    r"\bassertThat\(", r"\.get\(\)\s*[,)]", r"\.call\(\)",
    r"\bassertNotNull\(", r"\bassertNull\(",
]
# Signals that the only thing being checked is literal source text.
TEXT_ONLY_SIGNALS = [
    r"\.contains\(", r"\.indexOf\(", r"\.startsWith\(", r"\.endsWith\(",
    r"Pattern\.compile\(", r"\.matches\(",
]
CONTRACT_HINTS = [
    "Contract", "Invariant", "Policy", "Guard", "Gate", "Wiring", "Binding",
    "Ownership", "Compatibility", "Consistency", "Safety",
]

LONG_CASE_RX = re.compile(r"@Test")
METHOD_RX = re.compile(r"public\s+void\s+(\w+)\s*\(")


def classify(text):
    """Return (grade, reason, signals) for one test class."""
    behaviour = sum(1 for pat in BEHAVIOUR_SIGNALS if re.search(pat, text))
    text_only = sum(1 for pat in TEXT_ONLY_SIGNALS if re.search(pat, text))
    reads_source = bool(L.SOURCE_TEXT_RX.search(text))

    if behaviour >= 3 and text_only <= 2:
        return "A", "asserts runtime behaviour (captors/verify/values)", {
            "behaviour": behaviour, "text": text_only}
    if reads_source and text_only > 0 and behaviour == 0:
        return "C", "only literal source-text matching, no runtime assertion", {
            "behaviour": behaviour, "text": text_only}
    return "B", "mixed structural assertions; convert to type/interface contract", {
        "behaviour": behaviour, "text": text_only}


rows = []
for set_name in TEST_SETS:
    base = os.path.join(root, "app", "src", set_name)
    if not os.path.isdir(base):
        continue
    for path in L.walk_files(base, (".java",)):
        text = L.read_text(path)
        if not L.SOURCE_TEXT_RX.search(text):
            continue
        rel_path = L.rel(root, path)
        name = os.path.basename(rel_path)[:-5]
        grade, reason, signals = classify(text)
        # Which production files does it read? Needed for "what locks this file".
        targets = sorted({
            m.group(1) for m in re.finditer(r'readJava\(([^)]*)\)', text)
        })
        # Named .java targets it opens, e.g. read("src/main/.../Foo.java")
        file_targets = sorted({
            os.path.basename(m.group(1))
            for m in re.finditer(r'"([^"]*\.java)"', text)
        })
        rows.append({
            "class": name,
            "package": rel_path.split("/java/")[-1].rsplit("/", 1)[0].replace("/", "."),
            "set": set_name,
            "path": rel_path,
            "lines": L.count_lines(path),
            "cases": len(LONG_CASE_RX.findall(text)),
            "grade": grade,
            "reason": reason,
            "signals": signals,
            "targets": file_targets[:12],
        })

rows.sort(key=lambda r: (-r["cases"], r["class"]))
by_grade = {"A": 0, "B": 0, "C": 0}
for row in rows:
    by_grade[row["grade"]] += 1

# The 4 classes the plan singles out (379 cases) because they lock the two god
# classes and the focus-ring contract that stages 3/4 must rewrite.
HEAVY = {
    "VideoActivityLayoutTest": 159,
    "TmdbDetailActivityLayoutTest": 132,
    "TmdbUIAdapterTest": 61,
    "TvFocusRingContractTest": 27,
}
heavy_rows = []
for name, expected in HEAVY.items():
    match = [r for r in rows if r["class"] == name]
    if match:
        row = dict(match[0])
        row["expected_cases"] = expected
        heavy_rows.append(row)

report = {
    "schema_version": 1,
    "metric_counter": "source-text-classify-v1",
    "commit": git("rev-parse", "HEAD"),
    "totals": {
        "classes": len(rows),
        "cases": sum(r["cases"] for r in rows),
        "lines": sum(r["lines"] for r in rows),
    },
    "by_grade": by_grade,
    "by_set": {
        s: sum(1 for r in rows if r["set"] == s) for s in TEST_SETS
    },
    "heavy": heavy_rows,
    "classes": rows,
}

text = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
if json_out:
    with open(json_out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    print("wrote %s" % json_out)

print("classes=%d cases=%d lines=%d  A=%d B=%d C=%d"
      % (len(rows), report["totals"]["cases"], report["totals"]["lines"],
         by_grade["A"], by_grade["B"], by_grade["C"]))
if summary_only:
    for row in rows:
        print("%-1s %-4s %-5s %-46s %s"
              % (row["grade"], row["cases"], row["lines"], row["class"], row["reason"]))
PYEOF
rc=$?
if [[ $rc -ne 0 ]]; then echo "ERROR: source-text classification failed (rc=$rc)" >&2; exit 3; fi
