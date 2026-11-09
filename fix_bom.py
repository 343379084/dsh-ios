"""清理 BOM 并校验所有文本文件。

PowerShell 的 `Set-Content -Encoding utf8` 在 5.1 上会写 UTF-8 BOM，
而 Xcode 的 actool / JSON / YAML 解析器对 BOM 很敏感（Contents.json 带 BOM 会直接失败）。
这里统一归一化：去 BOM、统一 LF。
"""
import os
import sys
import json

ROOT = os.path.dirname(os.path.abspath(__file__))

TEXT_EXT = {".swift", ".json", ".yml", ".yaml", ".plist", ".css", ".js",
            ".sh", ".md", ".py", ".txt", ".gitignore"}
TEXT_NAMES = {".gitignore"}

BOM = b"\xef\xbb\xbf"


def iter_files():
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in ("__pycache__", ".git", "build", "Payload")]
        for fn in filenames:
            yield os.path.join(dirpath, fn)


def main():
    fixed_bom = []
    fixed_crlf = []
    bad_json = []

    for path in iter_files():
        name = os.path.basename(path)
        ext = os.path.splitext(name)[1].lower()
        if ext not in TEXT_EXT and name not in TEXT_NAMES:
            continue

        with open(path, "rb") as f:
            raw = f.read()

        changed = False

        if raw.startswith(BOM):
            raw = raw[len(BOM):]
            fixed_bom.append(os.path.relpath(path, ROOT))
            changed = True

        # .swift / .json / .yml / .css / .js / .sh 一律 LF；
        # .md / .txt 也统一 LF，避免 git 提示
        if b"\r\n" in raw:
            raw = raw.replace(b"\r\n", b"\n")
            fixed_crlf.append(os.path.relpath(path, ROOT))
            changed = True

        if changed:
            with open(path, "wb") as f:
                f.write(raw)

        # JSON 校验
        if ext == ".json":
            try:
                json.loads(raw.decode("utf-8"))
            except Exception as e:
                bad_json.append(f"{os.path.relpath(path, ROOT)}: {e}")

    print("== BOM 清理 ==")
    if fixed_bom:
        for p in fixed_bom:
            print("  去掉 BOM: " + p)
    else:
        print("  无需处理")

    print("\n== 换行符归一化 (CRLF -> LF) ==")
    if fixed_crlf:
        for p in fixed_crlf:
            print("  修正: " + p)
    else:
        print("  无需处理")

    print("\n== JSON 校验 ==")
    if bad_json:
        for p in bad_json:
            print("  !! " + p)
        sys.exit(1)
    print("  全部通过")

    if bad_json:
        sys.exit(1)
    print("\n✓ 完成")


if __name__ == "__main__":
    main()
