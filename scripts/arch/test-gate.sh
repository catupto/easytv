#!/usr/bin/env bash
# test-gate.sh — 单元测试门禁：把"失败 20 条能不能接受"从人眼判断变成机器判定。
#
# 契约（主方案 §6.9 / baseline README「21 条既有失败」）：
#   passed >= passed_floor  AND  当前失败集合 ⊆ known_failures
# 只满足前者不够：新增失败会被既有失败掩盖。
#
#   bash scripts/arch/test-gate.sh                 # 读已有 test-results，不跑 Gradle
#   bash scripts/arch/test-gate.sh --run           # 先跑两个变体的单测再判定（慢）
#   bash scripts/arch/test-gate.sh --variant mobile
#   bash scripts/arch/test-gate.sh --record-leanback  # 把当前 leanback 结果记为基线
#
# Exit: 0 通过, 1 回归, 2 用法/环境, 3 缺少测试结果或解析失败。
set -uo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: not in a Git worktree" >&2; exit 2; }
cd "$repo_root"

BASELINE_DIR="docs/refactoring/baseline"
RUN=0
VARIANT="both"
RECORD_LEANBACK=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run) RUN=1; shift ;;
    --variant) VARIANT="${2:-}"; shift 2 ;;
    --variant=*) VARIANT="${1#*=}"; shift ;;
    --record-leanback) RECORD_LEANBACK=1; shift ;;
    --baseline) BASELINE_DIR="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ $RUN -eq 1 ]]; then
  case "$VARIANT" in
    mobile)   tasks=(":app:testMobileArm64_v8aDebugUnitTest") ;;
    leanback) tasks=(":app:testLeanbackArm64_v8aDebugUnitTest") ;;
    both)     tasks=(":app:testMobileArm64_v8aDebugUnitTest" ":app:testLeanbackArm64_v8aDebugUnitTest") ;;
    *) echo "ERROR: --variant must be mobile|leanback|both" >&2; exit 2 ;;
  esac
  echo "==> 运行单测：${tasks[*]}（可能数分钟）"
  # 单测有既有失败时 Gradle 会非零退出，这里不看退出码，判定交给下面的脚本。
  bash gradlew "${tasks[@]}" || true
fi

PY=""
for candidate in python python3 py; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys' >/dev/null 2>&1; then
    PY="$candidate"; break
  fi
done
[[ -n "$PY" ]] || { echo "ERROR: no working Python (tried python, python3, py)" >&2; exit 2; }

# 同 guard.sh：不导出的话 Python 里的 subprocess(["bash", ...]) 会命中 WSL 的 bash。
export BASH

"$PY" - "$BASELINE_DIR" "$VARIANT" "$RECORD_LEANBACK" <<'PYEOF'
import glob
import json
import os
import sys
import xml.etree.ElementTree as ET

baseline_dir, variant, record_leanback = sys.argv[1], sys.argv[2], sys.argv[3] == "1"

with open(os.path.join(baseline_dir, "debt-baseline.json"), encoding="utf-8") as handle:
    debt = json.load(handle)
tests = debt["tests"]
known = {(row["class"], row["test"]) for row in tests["known_failures"]}
floor = int(tests["baseline"]["passed_floor"])

VARIANTS = {
    "mobile": ("mobileArm64_v8aDebug", ":app:testMobileArm64_v8aDebugUnitTest"),
    "leanback": ("leanbackArm64_v8aDebug", ":app:testLeanbackArm64_v8aDebugUnitTest"),
}
selected = ["mobile", "leanback"] if variant == "both" else [variant]
if any(v not in VARIANTS for v in selected):
    print("ERROR: --variant must be mobile|leanback|both", file=sys.stderr)
    sys.exit(2)


def collect(flavor):
    results = os.path.join("app", "build", "test-results", "test%sUnitTest" % flavor)
    if not os.path.isdir(results):
        return None
    total = failed = skipped = errors = 0
    failures = set()
    for path in glob.glob(os.path.join(results, "TEST-*.xml")):
        try:
            root = ET.parse(path).getroot()
        except ET.ParseError as exc:
            print("ERROR: cannot parse %s: %s" % (path, exc), file=sys.stderr)
            sys.exit(3)
        for case in root.iter("testcase"):
            total += 1
            status = "passed"
            if case.find("skipped") is not None:
                status = "skipped"
            elif case.find("failure") is not None:
                status = "failed"
            elif case.find("error") is not None:
                status = "error"
            if status == "skipped":
                skipped += 1
            elif status == "failed":
                failed += 1
                failures.add((case.get("classname", "").split(".")[-1], case.get("name", "")))
            elif status == "error":
                errors += 1
                failures.add((case.get("classname", "").split(".")[-1], case.get("name", "")))
    passed = total - failed - errors - skipped
    return {"total": total, "failed": failed, "errors": errors, "skipped": skipped,
            "passed": passed, "failures": failures}


problems = []
recorded = {}
for name in selected:
    flavor, task = VARIANTS[name]
    got = collect(flavor)
    if got is None:
        problems.append("%s: 没有测试结果（先跑 bash scripts/arch/test-gate.sh --run --variant %s）"
                        % (name, name))
        continue
    new = sorted(got["failures"] - known)
    print("[%s] tests=%d failed=%d errors=%d skipped=%d passed=%d"
          % (name, got["total"], got["failed"], got["errors"], got["skipped"], got["passed"]))
    if name == "mobile":
        if got["passed"] < floor:
            problems.append("mobile: passed %d < floor %d" % (got["passed"], floor))
        if new:
            problems.append("mobile: %d failure(s) outside known_failures" % len(new))
            for cls, test in new[:8]:
                print("    NEW FAILURE %s::%s" % (cls, test), file=sys.stderr)
    else:
        base_lb = tests.get("baseline_leanback")
        if base_lb:
            if got["passed"] < int(base_lb["passed_floor"]):
                problems.append("leanback: passed %d < floor %d"
                                % (got["passed"], int(base_lb["passed_floor"])))
            lb_known = {(r["class"], r["test"]) for r in base_lb.get("known_failures", [])}
            lb_new = sorted(got["failures"] - lb_known)
            if lb_new:
                problems.append("leanback: %d failure(s) outside its recorded baseline" % len(lb_new))
        elif record_leanback:
            recorded[name] = {
                "task": task, "flavor": flavor,
                "total_cases": got["total"], "failed": got["failed"],
                "skipped": got["skipped"], "passed_floor": got["passed"],
                "known_failures": [{"class": c, "test": t} for c, t in sorted(got["failures"])],
                "_rule": "Failure set must be a SUBSET of these entries AND passed >= passed_floor.",
            }
            print("[leanback] 已生成基线（写入前置条件：先人工确认这批失败都不是本批引入的）")
        else:
            print("[leanback] 未记录基线，仅报告（用 --record-leanback 建立）")

if recorded:
    out = os.path.join(baseline_dir, "_leanback-baseline.pending.json")
    with open(out, "w", encoding="utf-8") as handle:
        json.dump(recorded, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print("把下面内容并入 debt-baseline.json 的 tests.baseline_leanback：%s" % out)

if problems:
    print("\nTEST GATE FAILED:", file=sys.stderr)
    for line in problems:
        print("  " + line, file=sys.stderr)
    sys.exit(1)

print("\nTEST GATE OK: passed >= floor and no failure outside the recorded baseline.")
PYEOF
rc=$?
if [[ $rc -eq 1 ]]; then exit 1; fi
if [[ $rc -ne 0 ]]; then echo "ERROR: test gate evaluation failed (rc=$rc)" >&2; exit 3; fi
