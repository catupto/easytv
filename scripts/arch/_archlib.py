"""Shared measurement primitives for scripts/arch/*.sh.

Why a shared module: the master plan (§2.2.2, §4.8.3, §6.2) burned four rounds of
review on "same fact, three different numbers". Every口径 below is therefore
defined exactly once and consumed by all three scanners.

口径 (metric_counter = "regex-v1"), pinned by tests/verify against commit 91cdb8c:

  java_lines        `wc -l` semantics == count of b"\\n" (NOT splitlines()).
                    They differ by the number of files without a trailing newline.
  methods           line matches r'^\\s{0,8}(public|private|protected)[^;=]*\\('
                    Deliberately OVER-counts (anonymous-class methods, multi-line
                    declarations). Stability of口径 beats absolute accuracy (§R0-1).
  fields            r'^\\s{4}(private|protected|public)\\s+(?:static\\s+)?(?:final\\s+)?'
                    r'(?:volatile\\s+)?...\\s+(name)\\s*(?:=|;)'
                    Must be regex, not grep -c ';$' — grep misses multi-line init (228 vs 230).
  jaccard (L3)      strip each line, drop blanks, drop pure-comment lines
                    (//, *, /*), dedupe to a set, |A∩B| / |A∪B|.
  isLeanback        TWO numbers, never mixed:
                      raw      = grep -rn "isLeanback()"      -> plan §2.2.4 / §4 baseline (232)
                      callsite = raw minus declarations, comment-stripped body only
"""

import os
import re

# Source sets under app/src, in the order the plan reports them.
APP_SRC_SETS = (
    "main", "leanback", "mobile", "test", "testMobile", "testLeanback",
    "androidTest", "full", "debug",
)
# Extra Gradle modules carrying Java (settings.gradle).
EXTRA_MODULES = ("catvod", "quickjs", "chaquo", "nodejs")

# Directories never counted: generated output, VCS metadata, vendored binaries.
SKIP_DIRS = {"build", ".git", ".gradle", "third_party", "node_modules", ".idea"}

TV_PREFIX = "com/fongmi/android/tv/"
TEST_SETS = ("test", "testMobile", "testLeanback", "androidTest")
PROD_SETS = ("main", "leanback", "mobile")

METHOD_RX = re.compile(r"^\s{0,8}(public|private|protected)[^;=]*\(")
FIELD_RX = re.compile(
    r"^\s{4}(private|protected|public)\s+(?:static\s+)?(?:final\s+)?"
    r"(?:volatile\s+)?[A-Za-z0-9_<>\[\],\. ?]+?\s+([A-Za-z0-9_]+)\s*(?:=|;)"
)
IMPORT_RX = re.compile(r"^import\s+(?:static\s+)?com\.fongmi\.android\.tv\.(\w+)")
# C11 判定口径 — 5 patterns. 3 patterns only finds 193 files / 1,373 tests (plan §2.9.1).
SOURCE_TEXT_RX = re.compile(
    r"readJava\(|readSourceFile\(|Files\.readString\(|readMainJava|MainJavaPath"
)
ISLEANBACK_RX = re.compile(r"isLeanback\(\)")
ISLEANBACK_DECL_RX = re.compile(r"\bboolean\s+isLeanback\s*\(\s*\)\s*\{")
SETTING_REF_RX = re.compile(r"^import com\.fongmi\.android\.tv\.setting\.Setting;|\bSetting\.[a-zA-Z]", re.M)
SETTING_MEMBER_RX = re.compile(r"\bSetting\.[a-zA-Z_]+")
SETTING_USE_RX = re.compile(r"\bSetting\.[a-zA-Z_]+\s*\(")
APP_GET_RX = re.compile(r"\bApp\.get\(\)")
PLAYER_MANAGER_RX = re.compile(r"\bPlayerManager\b")
HISTORY_RX = re.compile(r"\bHistory\b")
EVENTBUS_RX = re.compile(r"EventBus")
MPV_NS_PREFIX = "app/src/main/java/androidx/media3/mpvplayer"


def rel(root, path):
    """Repo-relative path with forward slashes (JSON-stable on Windows)."""
    return os.path.relpath(path, root).replace(os.sep, "/")


def walk_files(root, suffixes=(".java",)):
    for base, dirs, files in os.walk(root):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
        for name in sorted(files):
            if name.endswith(suffixes):
                yield os.path.join(base, name)


def count_lines(path):
    """wc -l semantics: number of newline bytes, not number of logical lines."""
    with open(path, "rb") as handle:
        return handle.read().count(b"\n")


def read_text(path):
    with open(path, encoding="utf-8", errors="ignore") as handle:
        return handle.read()


def source_set(root, path):
    """Map a path to its Gradle source set / module bucket."""
    parts = rel(root, path).split("/")
    if len(parts) >= 3 and parts[0] == "app" and parts[1] == "src":
        return parts[2]
    if parts and parts[0] in EXTRA_MODULES:
        return parts[0]
    return "(other)"


def top_package(root, path):
    """Top-level package bucket inside com.fongmi.android.tv, else the namespace."""
    rel_path = rel(root, path)
    if rel_path.startswith(MPV_NS_PREFIX + "/"):
        return "androidx/media3/mpvplayer"
    idx = rel_path.find("/" + TV_PREFIX)
    if idx < 0:
        if rel_path.startswith(TV_PREFIX):
            rest = rel_path[len(TV_PREFIX):]
        else:
            return "(root)"
    else:
        rest = rel_path[idx + len(TV_PREFIX) + 1:]
    return rest.split("/")[0] if "/" in rest else "(root)"


def strip_comments(text):
    """Return the text with // and /* */ comments removed, preserving line count."""
    out = []
    in_block = False
    for line in text.splitlines():
        buf = []
        i = 0
        while i < len(line):
            if in_block:
                end = line.find("*/", i)
                if end < 0:
                    i = len(line)
                    break
                in_block = False
                i = end + 2
            else:
                line_comment = line.find("//", i)
                block_start = line.find("/*", i)
                candidates = [x for x in (line_comment, block_start) if x >= 0]
                if not candidates:
                    buf.append(line[i:])
                    i = len(line)
                else:
                    first = min(candidates)
                    buf.append(line[i:first])
                    if first == line_comment:
                        i = len(line)
                    else:
                        in_block = True
                        i = first + 2
        out.append("".join(buf))
    return "\n".join(out)


def code_only(text):
    return strip_comments(text)


def jaccard_set(text):
    """L3 口径: strip, drop blanks, drop pure-comment lines, dedupe."""
    lines = set()
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("//") or line.startswith("*") or line.startswith("/*"):
            continue
        lines.add(line)
    return lines


def jaccard(left, right):
    union = left | right
    return (len(left & right) / len(union)) if union else 1.0


def jaccard_bucket(value):
    if value >= 1.0 - 1e-12:
        return "1.000"
    if value >= 0.95:
        return "0.95-1.0"
    if value >= 0.90:
        return "0.90-0.95"
    if value >= 0.85:
        return "0.85-0.90"
    if value >= 0.70:
        return "0.70-0.85"
    if value >= 0.50:
        return "0.50-0.70"
    return "<0.50"


def is_test_set(name):
    return name in TEST_SETS


def is_prod_set(name):
    return name in PROD_SETS


def java_file_metrics(root):
    """Per-file structural metrics for every Java file in the tree."""
    rows = []
    for path in walk_files(root, (".java",)):
        text = read_text(path)
        lines = text.splitlines()
        rows.append({
            "path": rel(root, path),
            "set": source_set(root, path),
            "package": top_package(root, path),
            "lines": count_lines(path),
            "methods": sum(1 for line in lines if METHOD_RX.match(line)),
            "fields": sum(1 for line in lines if FIELD_RX.match(line)),
        })
    return rows


def flavor_dup_map(root):
    """Same-path Java files present in BOTH leanback and mobile source sets."""
    leanback = "app/src/leanback/java"
    mobile = "app/src/mobile/java"
    left, right = set(), set()
    for base, target in ((leanback, left), (mobile, right)):
        full = os.path.join(root, base)
        if not os.path.isdir(full):
            continue
        for path in walk_files(full, (".java",)):
            target.add(os.path.relpath(path, full).replace(os.sep, "/"))
    return leanback, mobile, sorted(left & right)


def main_overrides(root):
    """Flavor files that shadow a same-path file in main (must stay 0, plan §2.2.1)."""
    main = "app/src/main/java"
    main_set = set()
    full_main = os.path.join(root, main)
    if os.path.isdir(full_main):
        for path in walk_files(full_main, (".java",)):
            main_set.add(os.path.relpath(path, full_main).replace(os.sep, "/"))
    result = {}
    for flavor in ("leanback", "mobile"):
        base = os.path.join(root, "app/src", flavor, "java")
        hits = set()
        if os.path.isdir(base):
            for path in walk_files(base, (".java",)):
                name = os.path.relpath(path, base).replace(os.sep, "/")
                if name in main_set:
                    hits.add(name)
        result[flavor] = sorted(hits)
    return result
