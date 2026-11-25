#!/usr/bin/env python3
"""生成 WebHTV/easytv 的更新清单 JSON。

清单结构与 .github/workflows/android-release.yml 中 CI 生成的完全一致，
字段含义见 app/src/main/java/com/fongmi/android/tv/bean/Update.java 与 Updater.readUpdate()。

用法:
    python scripts/gen_update_manifest.py \
        --tag v1.0.0 --version-name 1.0.0 --version-code 1 \
        --channel stable --dist dist
"""
import argparse
import glob
import hashlib
import json
import os
import sys

REPO = "hjdhnx/easytv"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", required=True)
    ap.add_argument("--version-name", required=True)
    ap.add_argument("--version-code", required=True, type=int)
    ap.add_argument("--channel", default="stable", choices=["stable", "beta"])
    ap.add_argument("--dist", default="dist")
    ap.add_argument("--notes", default="")
    ap.add_argument("--repo", default=REPO)
    args = ap.parse_args()

    download_base = f"https://github.com/{args.repo}/releases/download/{args.tag}"
    apks = sorted(glob.glob(os.path.join(args.dist, "*.apk")))
    if not apks:
        sys.exit(f"no APK found in {args.dist}")

    for apk in apks:
        base = os.path.splitext(os.path.basename(apk))[0]
        with open(apk, "rb") as fh:
            content = fh.read()
        data = {
            "name": args.tag,
            "versionName": args.version_name,
            "desc": f"{args.tag} - {args.version_name}",
            "channel": args.channel,
            "code": args.version_code,
            "apk": f"{download_base}/{base}.apk",
            "size": len(content),
            "sha256": hashlib.sha256(content).hexdigest(),
            "downloads": {
                "github": {"url": f"{download_base}/{base}.apk"},
            },
        }
        if args.notes:
            data["notes"] = args.notes
        out = os.path.join(args.dist, f"{base}.json")
        with open(out, "w", encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
        print(f"wrote {out}  ({data['size']} bytes, sha256={data['sha256'][:16]}...)")


if __name__ == "__main__":
    main()
