#!/usr/bin/env bash
# guard.sh — the "只减不增" gate. Fails if any metric is WORSE than the frozen baseline.
#
# Contract (master plan §6.2/§6.9): every debt item has a baseline; the current set
# must be a SUBSET of it and every count must be <= its baseline number. A file
# that leaves the debt list must also be removed from the baseline (so the
# whitelist cannot rot into a permanent exemption) — warn-only, not a failure,
# because removing entries is exactly what a refactor batch is supposed to do.
#
# The whole point (ADR-0001): no code movement before this can go red. Verified by
# --self-test, which injects a synthetic regression and asserts exit 1.
#
#   bash scripts/arch/guard.sh [--baseline DIR] [--current m.json,d.json,u.json]
#                              [--self-test]
#
# Exit: 0 pass, 1 metric regression, 2 usage/env, 3 measurement failure.
set -uo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: not in a Git worktree" >&2; exit 2; }
cd "$repo_root"

BASELINE_DIR="docs/refactoring/baseline"
CURRENT=""
SELF_TEST=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --baseline) BASELINE_DIR="${2:-}"; shift 2 ;;
    --baseline=*) BASELINE_DIR="${1#*=}"; shift ;;
    --current) CURRENT="${2:-}"; shift 2 ;;
    --current=*) CURRENT="${1#*=}"; shift ;;
    --self-test) SELF_TEST=1; shift ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

PY=""
for candidate in python python3 py; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys' >/dev/null 2>&1; then
    PY="$candidate"; break
  fi
done
[[ -n "$PY" ]] || { echo "ERROR: no working Python (tried python, python3, py)" >&2; exit 2; }

# 导出当前 shell 的解释器路径，供 Python 侧 subprocess 复用。
# 不导出的话 Python 里 subprocess(["bash", ...]) 会经 PATH 命中
# C:\Windows\System32\bash.exe（WSL 启动器），在未装 WSL / 被安全策略拦截时
# 直接 rc=1，且 stderr 是 GBK/UTF-16 错误文本 —— 门禁会因此无法运行。
export BASH

"$PY" - "$BASELINE_DIR" "$CURRENT" "$SELF_TEST" <<'PYEOF'
import json
import os
import subprocess
import sys
import tempfile

baseline_dir = sys.argv[1]
current_arg = sys.argv[2] if len(sys.argv) > 2 else ""
self_test = sys.argv[3] == "1" if len(sys.argv) > 3 else False

root = os.getcwd()
arch = os.path.join(root, "scripts", "arch")


def run(script, out_path, *extra):
    # 必须用启动本脚本的那个 bash（Git-Bash），不能用裸 "bash"：
    # 从 Python 的 subprocess 里 "bash" 会经 PATH 解析到 C:\Windows\System32\bash.exe
    # （WSL 启动器），在 WSL 未安装/被安全策略拦截时返回 rc=1 且 stderr 是 GBK 错误文本。
    # 显式指定编码 + errors=replace，避免把 GBK 文本按 UTF-8 解码时抛 UnicodeDecodeError。
    return subprocess.run(
        [os.environ.get("BASH") or "bash", os.path.join(arch, script), "--json-out", out_path] + list(extra),
        capture_output=True, text=True, encoding="utf-8", errors="replace", check=False)


def measure(tmpdir):
    """Produce the three current JSONs; returns (metrics, deps, dup) or raises."""
    paths = {}
    for script, key in (("metrics.sh", "metrics"), ("dep-graph.sh", "deps"), ("dup-scan.sh", "dup")):
        out = os.path.join(tmpdir, key + ".json")
        result = run(script, out)
        if result.returncode != 0:
            raise SystemExit("ERROR: %s failed (rc=%d): %s"
                             % (script, result.returncode, (result.stderr or "").strip()[:400]))
        with open(out, encoding="utf-8") as handle:
            paths[key] = json.load(handle)
    return paths["metrics"], paths["deps"], paths["dup"]


def load_base(name):
    path = os.path.join(baseline_dir, name)
    if not os.path.isfile(path):
        raise SystemExit("ERROR: missing baseline file: %s" % path)
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


failures = []
warnings = []

# 容差只给"行数/成员数"这类会被机械替换带偏的指标：把 Util.isLeanback() 换成
# DeviceModePolicy.current().isTv() 会让所在行变长并可能折行，+1~+5 行属于噪声。
# 集合与计数类指标（调用点、文件数、双份文件、环）一律零容差。
TOLERANCE_PCT = 0.01
TOLERANCE_CAP = 50


def tolerance(base):
    return min(int(base * TOLERANCE_PCT), TOLERANCE_CAP)


def drift_increment(label):
    total = 0
    for entry in drift.get("entries", []):
        if entry.get("metric") == label and entry.get("kind", "increment") == "increment":
            total += int(entry.get("increment", 0))
    return total


def drift_allows_item(label, item):
    """集合类指标的唯一豁免通道：必须点名具体条目，且同样带失效阶段。"""
    for entry in drift.get("entries", []):
        if entry.get("metric") != label or entry.get("kind") != "new_item":
            continue
        allowed = entry.get("items", [])
        if isinstance(item, tuple):
            hit = any(tuple(x) == item for x in allowed if isinstance(x, (list, tuple)))
        else:
            hit = item in allowed
        if hit:
            return True
    return False


def check_at_most(label, current, base, pinned_value=None, tolerant=False):
    # 同时受工作基线与 pinned 地板约束，取更严者；两边任一被抬高都绕不过去。
    strict = base if pinned_value is None else min(base, pinned_value)
    ceiling = strict + (tolerance(strict) if tolerant else 0) + drift_increment(label)
    if current > ceiling:
        origin = ""
        if pinned_value is not None and pinned_value != base:
            origin = " [working=%s pinned=%s]" % (base, pinned_value)
        failures.append("%s: %s > ceiling %s%s" % (label, current, ceiling, origin))


def check_subset(label, current_set, base_set, pinned_set=None):
    current = set(current_set)
    # 必须同时是工作基线与 pinned 地板的上集约束下的子集：任一记录里没有的都算新增。
    for name, recorded in (("baseline", base_set), ("pinned", pinned_set)):
        if recorded is None:
            continue
        new = sorted(item for item in current - set(recorded)
                     if not drift_allows_item(label, item))
        if new:
            failures.append("%s: %d item(s) not in %s" % (label, len(new), name))
            # Showing 5 keeps the output readable when a refactor adds many at once.
            for item in new[:5]:
                failures.append("    + %s" % (item,))
    removed = sorted(set(base_set) - current)
    if removed:
        warnings.append("%s: %d baseline entr(ies) no longer present — prune them "
                        "from debt-baseline.json in the same commit" % (label, len(removed)))


def check_drift_entries():
    """豁免条目本身也要被守：字段缺失、越权、过了失效阶段都判红。"""
    for index, entry in enumerate(drift.get("entries", [])):
        where = "approved-drift[%d]" % index
        kind = entry.get("kind", "increment")
        for field in ("metric", "batch", "reason", "expires_stage"):
            if field not in entry:
                failures.append("%s: missing field '%s'" % (where, field))
        if not str(entry.get("reason", "")).strip():
            failures.append("%s: empty reason (an unjustified exemption is not an exemption)" % where)
        if kind == "increment":
            if int(entry.get("increment", 0)) <= 0:
                failures.append("%s: increment must be positive" % where)
        elif kind == "new_item":
            if not entry.get("items"):
                failures.append("%s: new_item must name the allowed item(s)" % where)
        else:
            failures.append("%s: unknown kind '%s'" % (where, kind))
        expires = entry.get("expires_stage")
        if isinstance(expires, int) and CURRENT_STAGE >= expires:
            failures.append("%s: drifted allowance expired at stage %s (current stage %s) — "
                            "delete the entry or close the debt" % (where, expires, CURRENT_STAGE))


def guard(metrics, deps, dup, debt):
    totals = metrics["totals"]
    base_totals = debt["totals"]
    pin_totals = pinned["totals"]
    # File/line counts may grow briefly while a batch adds scaffolding, so they are
    # gated by the ceiling (never by equality); the real floor is the pass count.
    check_at_most("totals.java_files", totals["java_files"],
                  base_totals["java_files_max"], pin_totals["java_files_max"])
    check_at_most("totals.java_lines", totals["java_lines"],
                  base_totals["java_lines_max"], pin_totals["java_lines_max"], tolerant=True)

    ext = metrics["extremes"]
    # max_file_lines / max_methods / max_package_lines 属于会随机械替换漂移的量，给容差；
    # max_fields / max_direct_classes 变化只可能来自真的加了成员，零容差。
    tolerant_extremes = {"max_file_lines", "max_methods", "max_package_lines"}
    for key in ("max_file_lines", "max_methods", "max_fields",
                "max_package_lines", "max_direct_classes"):
        check_at_most("extremes." + key, ext[key], debt["extremes"][key],
                      pinned["extremes"][key], tolerant=(key in tolerant_extremes))

    for bucket in ("over_1000", "over_2000", "over_3000"):
        check_at_most("distribution." + bucket, metrics["distribution"][bucket],
                      debt["distribution"][bucket], pinned["distribution"][bucket])

    # Large files: current set must be a subset of the frozen list, and each file's
    # own line count must not exceed its frozen value.
    large = {r["path"]: r["lines"] for r in metrics.get("large_files", [])}
    check_subset("large_files", large.keys(), debt["large_files"].keys(),
                 pinned["large_files"].keys())
    for path, lines in large.items():
        check_at_most("large_file:%s" % path.split("/")[-1], lines,
                      debt["large_files"][path], pinned["large_files"].get(path),
                      tolerant=True)

    check_at_most("flavor.dup_files", metrics["flavor"]["dup_files"],
                  debt["flavor"]["dup_files_max"], pinned["flavor"]["dup_files_max"])
    check_at_most("flavor.dup_lines", metrics["flavor"]["dup_lines"],
                  debt["flavor"]["dup_lines_max"], pinned["flavor"]["dup_lines_max"], tolerant=True)
    check_subset("flavor.dup_files", dup["dup_files_list"], debt["flavor"]["dup_files"],
                 pinned["flavor"]["dup_files"])
    for flavor, count in dup["main_overrides"].items():
        if count:
            failures.append("flavor.main_overrides[%s]: %d (flavor must not shadow main)" % (flavor, count))

    check_at_most("deps.bidirectional_pairs", deps["bidirectional_pairs"],
                  debt["deps"]["bidirectional_pairs_max"],
                  pinned["deps"]["bidirectional_pairs_max"])
    base_pairs = {tuple(p) for p in debt["deps"]["bidirectional_pairs"]}
    pin_pairs = {tuple(p) for p in pinned["deps"]["bidirectional_pairs"]}
    current_pairs = {(e["a"], e["b"]) for e in deps["bidirectional"]}
    check_subset("deps.bidirectional_pairs", current_pairs, base_pairs, pin_pairs)
    check_at_most("deps.ui_to_player_files", deps["ui_to_player_files"],
                  debt["deps"]["ui_to_player_files_max"],
                  pinned["deps"]["ui_to_player_files_max"])

    off = metrics["offenders"]
    # Explicit key list: debt-baseline.json also carries "_note" keys, and iterating
    # the dict would try to compare a list of strings against an int.
    for key in ("isLeanback_callsites", "setting_static_callsites", "setting_static_files",
                "app_get_files", "player_manager_files", "bean_history_files",
                "eventbus_files", "androidx_namespace_files"):
        check_at_most("offenders." + key, off[key], debt["offenders"][key],
                      pinned["offenders"][key])

    check_subset("namespace_files", dup["namespace_files_list"], debt["namespace_files"],
                 pinned["namespace_files"])
    check_at_most("tests.source_text_locks", metrics["tests"]["source_text_locks"],
                  debt["tests"]["source_text_locks_max"],
                  pinned["tests"]["source_text_locks_max"])
    check_at_most("tests.source_text_lock_cases", metrics["tests"]["source_text_lock_cases"],
                  debt["tests"]["source_text_lock_cases_max"],
                  pinned["tests"]["source_text_lock_cases_max"])

    check_drift_entries()


debt = load_base("debt-baseline.json")
# 不可变地板 + 显式增长通道。两者缺失都按"门禁配置错误"处理，不允许静默降级为
# 只看工作基线——那正是上一轮把基线改成现实、门禁变成橡皮章的原因。
pinned = load_base("debt-baseline.pinned.json")
drift = load_base("approved-drift.json")
CURRENT_STAGE = int(drift.get("stage", 0))

if current_arg:
    # Explicit artifacts: the caller already ran metrics/dep-graph/dup-scan.
    paths = [p.strip() for p in current_arg.split(",") if p.strip()]
    if len(paths) != 3:
        raise SystemExit("ERROR: --current needs metrics.json,deps.json,dup.json")
    loaded = []
    for path in paths:
        # Accept both Git-Bash (`/tmp/x.json`, rewritten by the shell) and native
        # Windows paths. bash passes /tmp through verbatim on some setups, which the
        # Windows Python build cannot open, so resolve it via cygpath when available.
        if not os.path.isfile(path):
            converted = subprocess.run(["cygpath", "-w", path], capture_output=True,
                                       text=True, encoding="utf-8", errors="replace",
                                       check=False).stdout.strip()
            if converted and os.path.isfile(converted):
                path = converted
        if not os.path.isfile(path):
            raise SystemExit("ERROR: cannot read current artifact: %s" % path)
        with open(path, encoding="utf-8") as handle:
            loaded.append(json.load(handle))
    guard(loaded[0], loaded[1], loaded[2], debt)
elif self_test:
    # ADR-0001 requires proving the gate CAN go red, not just that it is green.
    with tempfile.TemporaryDirectory() as tmp:
        metrics, deps, dup = measure(tmp)
        before = len(failures)
        guard(metrics, deps, dup, debt)
        clean = len(failures)
        if clean != before:
            print("SELF-TEST FAILED: current tree is already in violation:", file=sys.stderr)
            for line in failures:
                print("  " + line, file=sys.stderr)
            sys.exit(1)

        # Inject one synthetic regression per guard family and assert each goes red.
        mfl_base = min(debt["extremes"]["max_file_lines"], pinned["extremes"]["max_file_lines"])
        probes = [
            ("dup_files grows by 1",
             lambda: dup.__setitem__("dup_files_list", dup["dup_files_list"] + ["ui/activity/Injected.java"])),
            ("bidirectional pair added",
             lambda: deps["bidirectional"].append({"a": "zzz", "b": "yyy", "a_to_b": 1, "b_to_a": 1})),
            ("max_file_lines grows beyond tolerance",
             lambda: metrics["extremes"].__setitem__("max_file_lines",
                                                     mfl_base + tolerance(mfl_base) + 1)),
            ("isLeanback callsites grow (zero tolerance)",
             lambda: metrics["offenders"].__setitem__("isLeanback_callsites",
                                                      metrics["offenders"]["isLeanback_callsites"] + 1)),
            ("source_text_locks grow",
             lambda: metrics["tests"].__setitem__("source_text_locks",
                                                  metrics["tests"]["source_text_locks"] + 1)),
            ("flavor shadows main",
             lambda: dup["main_overrides"].__setitem__("leanback", 1)),
        ]
        for label, mutate in probes:
            saved_m = json.loads(json.dumps(metrics))
            saved_d = json.loads(json.dumps(deps))
            saved_u = json.loads(json.dumps(dup))
            mutate()
            del failures[:]
            guard(metrics, deps, dup, debt)
            if not failures:
                print("SELF-TEST FAILED: guard stayed green when '%s'" % label, file=sys.stderr)
                sys.exit(1)
            metrics.clear(); metrics.update(saved_m)
            deps.clear(); deps.update(saved_d)
            dup.clear(); dup.update(saved_u)
        # 容差不等于豁免：正好落在容差内的增长必须仍然通过，超出一行才红。
        saved_mfl = metrics["extremes"]["max_file_lines"]
        metrics["extremes"]["max_file_lines"] = mfl_base + tolerance(mfl_base)
        del failures[:]
        guard(metrics, deps, dup, debt)
        if failures:
            print("SELF-TEST FAILED: growth inside tolerance must stay green, got: %s"
                  % failures, file=sys.stderr)
            sys.exit(1)
        metrics["extremes"]["max_file_lines"] = saved_mfl

        # 过期豁免必须判红，否则"临时豁免"会变成永久豁免。
        saved_entries = list(drift.get("entries", []))
        drift["entries"] = [{
            "metric": "extremes.max_file_lines", "increment": 1, "batch": "self-test",
            "reason": "probe", "expires_stage": max(CURRENT_STAGE, 0),
        }]
        del failures[:]
        guard(metrics, deps, dup, debt)
        expired = [f for f in failures if "expired" in f]
        drift["entries"] = saved_entries
        del failures[:]
        if not expired:
            print("SELF-TEST FAILED: an expired drift allowance was accepted", file=sys.stderr)
            sys.exit(1)

        print("SELF-TEST OK: current tree is clean, all %d synthetic regressions were caught, "
              "tolerance boundary and drift expiry both behave." % len(probes))
        sys.exit(0)
else:
    with tempfile.TemporaryDirectory() as tmp:
        metrics, deps, dup = measure(tmp)
        guard(metrics, deps, dup, debt)

if warnings:
    for line in warnings:
        print("PRUNE: " + line)

if failures:
    print("GUARD FAILED: %d metric regression(s) vs %s" % (len(failures) // 1, baseline_dir),
          file=sys.stderr)
    for line in failures:
        print("  " + line, file=sys.stderr)
    sys.exit(1)

print("GUARD OK: all metrics are at or better than baseline (%s)" % baseline_dir)
PYEOF
rc=$?
if [[ $rc -eq 1 ]]; then exit 1; fi
if [[ $rc -ne 0 ]]; then echo "ERROR: guard evaluation failed (rc=$rc)" >&2; exit 3; fi
