#!/usr/bin/env bash
# 从基线提交提取内置 so，生成外置内核包（zip + sha256）。
# 用法：bash scripts/build_external_cores.sh [基线commit] [输出目录]
# 默认基线：ece01064451ff1cd3167587329c3f80aae1462cc（外置改造前的全量快照）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
BASE="${1:-ece01064451ff1cd3167587329c3f80aae1462cc}"
OUT="${2:-$ROOT/ext/cores-build}"
cd "$ROOT"

command -v 7z >/dev/null 2>&1 || { echo "7z is required" >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum is required" >&2; exit 1; }

mkdir -p "$OUT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# core -> 基线里 so 的目录前缀；so 在 zip 内平铺存放（加载器按 core/<abi>/ 解压后按文件名 System.load）
pack() {
  local core="$1" abi="$2" prefix="$3"
  shift 3
  local stage="$TMP/$core-$abi"
  mkdir -p "$stage"
  local name
  for name in "$@"; do
    git show "$BASE:$prefix/$name" > "$stage/$name"
  done
  local zipfile="$OUT/$core-$abi.zip"
  rm -f "$zipfile"
  (cd "$stage" && 7z a -tzip -mx=9 -bso0 -bsp0 "$zipfile" . >/dev/null)
  sha256sum "$zipfile" | awk '{print $1}' > "$zipfile.sha256"
  local mb
  mb="$(awk -v s="$(stat -c%s "$zipfile")" 'BEGIN{printf "%.1f", s/1048576}')"
  printf '%-16s %6s MB  %s\n' "$core-$abi" "$mb" "$(cat "$zipfile.sha256")"
}

echo "Building external core packages from $BASE -> $OUT"
MPV_NAMES="libc++_shared.so libmpv.so libmvcodec.so libmvdevice.so libmvfilter.so libmvformat.so libmvutil.so libmwresample.so libmwscale.so libplayer.so"
for abi in arm64-v8a armeabi-v7a; do
  flavor=$([ "$abi" = arm64-v8a ] && echo arm64_v8a || echo armeabi_v7a)
  # shellcheck disable=SC2086
  pack mpv "$abi" "app/src/$flavor/assets/mpv-libs/$abi" $MPV_NAMES
  # shellcheck disable=SC2086
  pack ijk "$abi" "app/src/main/jniLibs/$abi" libijkffmpeg.so libijkplayer.so libijksdl.so
  pack sherpa "$abi" "app/src/main/jniLibs/$abi" libsherpa-onnx-jni.so
done
echo "Done. Copy the .zip and .sha256 pairs to <external-files>/ext/cores/ on device."
