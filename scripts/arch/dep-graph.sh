#!/usr/bin/env bash
# dep-graph.sh — top-level package dependency graph, bidirectional pairs, cycles.
#
# Contract (master plan §6.2/§6.4): import-level edges between top-level packages
# under com.fongmi.android.tv, the count of pairs where A->B and B->A both exist
# (baseline 52, target <=20 then 0), and a cycle list for review.
#
# Only STATIC imports are counted (the plan's口径). Fully-qualified inline usage is
# not an import and is deliberately excluded so the number stays comparable.
#
#   bash scripts/arch/dep-graph.sh [--json-out PATH] [--diff PATH]
#
# --diff compares against a saved JSON and prints newly-added edges/deps.
# Exit: 0 ok, 2 usage/environment, 3 measurement failure.
set -uo pipefail

JSON_OUT=""
DIFF_AGAINST=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json-out) JSON_OUT="${2:-}"; shift 2 ;;
    --json-out=*) JSON_OUT="${1#*=}"; shift ;;
    --diff) DIFF_AGAINST="${2:-}"; shift 2 ;;
    --diff=*) DIFF_AGAINST="${1#*=}"; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
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

"$PY" - "$JSON_OUT" "$DIFF_AGAINST" <<'PYEOF'
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.join("scripts", "arch"))
import _archlib as L

json_out = sys.argv[1] if len(sys.argv) > 1 else ""
diff_against = sys.argv[2] if len(sys.argv) > 2 else ""


def git(*args):
    try:
        return subprocess.run(("git",) + args, capture_output=True, text=True,
                              check=False).stdout.strip()
    except OSError:
        return ""


root = os.getcwd()
MAIN = os.path.join(root, "app", "src", "main", "java")

# edges[(src, dst)] = number of import lines
edges = {}
# edge_files[(src, dst)] = set of files creating the edge (for "which file" reports)
edge_files = {}
files_by_package = {}

for path in L.walk_files(MAIN, (".java",)):
    rel_path = L.rel(root, path)
    pkg = L.top_package(root, path)
    files_by_package.setdefault(pkg, set()).add(rel_path)
    for line in L.read_text(path).splitlines():
        match = L.IMPORT_RX.match(line)
        if not match:
            continue
        dst = match.group(1)
        if dst == pkg:
            continue
        edges[(pkg, dst)] = edges.get((pkg, dst), 0) + 1
        edge_files.setdefault((pkg, dst), set()).add(rel_path)

packages = sorted({p for pair in edges for p in pair})
bidirectional = []
for (src, dst), forward in sorted(edges.items()):
    if src < dst and (dst, src) in edges:
        backward = edges[(dst, src)]
        bidirectional.append({
            "a": src, "b": dst,
            "a_to_b": forward, "b_to_a": backward,
            "total": forward + backward,
        })
bidirectional.sort(key=lambda e: (-e["total"], e["a"], e["b"]))

# Cycles: Tarjan SCC over the package graph. Any SCC with >1 node is a cycle;
# a bidirectional pair is the minimal 2-cycle and shows up here too.
adjacency = {}
for (src, dst) in edges:
    adjacency.setdefault(src, set()).add(dst)
for pkg in packages:
    adjacency.setdefault(pkg, set())

index_of, lowlink, on_stack, stack, sccs = {}, {}, set(), [], []
counter = [0]


def strongconnect(node):
    index_of[node] = lowlink[node] = counter[0]
    counter[0] += 1
    stack.append(node)
    on_stack.add(node)
    for neighbour in sorted(adjacency.get(node, ())):
        if neighbour not in index_of:
            strongconnect(neighbour)
            lowlink[node] = min(lowlink[node], lowlink[neighbour])
        elif neighbour in on_stack:
            lowlink[node] = min(lowlink[node], index_of[neighbour])
    if lowlink[node] == index_of[node]:
        component = []
        while True:
            member = stack.pop()
            on_stack.discard(member)
            component.append(member)
            if member == node:
                break
        sccs.append(sorted(component))


for pkg in sorted(adjacency):
    if pkg not in index_of:
        strongconnect(pkg)

cycles = sorted((c for c in sccs if len(c) > 1), key=lambda c: (-len(c), c))

# ui -> player direct imports (§6.1: 36 files, target 0).
ui_to_player_files = sorted({
    f for (src, dst), fs in edge_files.items()
    if src == "ui" and dst == "player" for f in fs
})

report = {
    "schema_version": 1,
    "metric_counter": "import-static-v1",
    "commit": git("rev-parse", "HEAD"),
    "scope": "app/src/main/java/com/fongmi/android/tv (top-level packages)",
    "packages": packages,
    "package_count": len(packages),
    "edge_count": len(edges),
    "edges": [
        {"from": src, "to": dst, "imports": count}
        for (src, dst), count in sorted(edges.items(), key=lambda kv: (-kv[1], kv[0]))
    ],
    "bidirectional_pairs": len(bidirectional),
    "bidirectional": bidirectional,
    "cycle_count": len(cycles),
    "cycles": cycles,
    "ui_to_player_files": len(ui_to_player_files),
    "ui_to_player_list": ui_to_player_files,
}

text = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
if json_out:
    with open(json_out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    print("wrote %s" % json_out)
    print("bidirectional_pairs=%d cycles=%d edges=%d ui_to_player_files=%d"
          % (report["bidirectional_pairs"], report["cycle_count"],
             report["edge_count"], report["ui_to_player_files"]))
else:
    sys.stdout.write(text)

if diff_against:
    with open(diff_against, encoding="utf-8") as handle:
        base = json.load(handle)
    base_pairs = {(e["a"], e["b"]) for e in base.get("bidirectional", [])}
    new_pairs = sorted(p for p in {(e["a"], e["b"]) for e in bidirectional}
                       if p not in base_pairs)
    base_edges = {(e["from"], e["to"]) for e in base.get("edges", [])}
    new_edges = sorted(p for p in set(edges) if p not in base_edges)
    if new_pairs or new_edges:
        print("REGRESSION: %d new bidirectional pair(s), %d new edge(s)" % (len(new_pairs), len(new_edges)))
        for pair in new_pairs:
            print("  new cycle: %s <-> %s" % pair)
        for pair in new_edges:
            print("  new edge:  %s -> %s" % pair)
        sys.exit(1)
    print("OK: no new edges or bidirectional pairs vs %s" % diff_against)
PYEOF
rc=$?
if [[ $rc -eq 1 ]]; then exit 1; fi
if [[ $rc -ne 0 ]]; then echo "ERROR: dep-graph measurement failed (rc=$rc)" >&2; exit 3; fi
