"""Swift / JS / CSS 静态自检：在没有 macOS 的情况下先抓结构性错误。

做四件事：
1. 逐文件剥掉字符串、注释、字符字面量后检查 {} () [] 平衡
2. 检查 Swift 文件是否都有 import
3. 检查是否有重复的 `var body` / `let body` 声明（SwiftUI 高频坑）
4. 检查 Swift 里引用的 Theme.* / AppSettings 成员是否真实存在
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
APP = os.path.join(ROOT, "DSHMobile")

BRACKETS = {"{": "}", "(": ")", "[": "]"}


def strip_code(src: str) -> str:
    """去掉 // 行注释、/* */ 块注释、双引号字符串、三引号字符串、字符字面量。"""
    out = []
    i = 0
    n = len(src)
    while i < n:
        c = src[i]
        # 三引号
        if src.startswith('"""', i):
            j = src.find('"""', i + 3)
            i = n if j < 0 else j + 3
            out.append('""')
            continue
        # 行注释
        if src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
            continue
        # 块注释（支持嵌套一层）
        if src.startswith("/*", i):
            depth = 1
            i += 2
            while i < n and depth > 0:
                if src.startswith("/*", i):
                    depth += 1
                    i += 2
                elif src.startswith("*/", i):
                    depth -= 1
                    i += 2
                else:
                    i += 1
            continue
        # 字符串
        if c == '"':
            i += 1
            while i < n:
                if src[i] == "\\":
                    i += 2
                    continue
                if src[i] == '"':
                    i += 1
                    break
                i += 1
            out.append('""')
            continue
        out.append(c)
        i += 1
    return "".join(out)


def check_balance(path: str) -> list:
    with open(path, "r", encoding="utf-8") as f:
        raw = f.read()
    src = strip_code(raw)
    stack = []
    line = 1
    errors = []
    for ch in src:
        if ch == "\n":
            line += 1
        if ch in BRACKETS:
            stack.append((ch, line))
        elif ch in BRACKETS.values():
            if not stack:
                errors.append(f"{os.path.basename(path)}:{line} 多余的闭合 {ch}")
                continue
            op, ln = stack.pop()
            if BRACKETS[op] != ch:
                errors.append(f"{os.path.basename(path)}:{line} 期望 {BRACKETS[op]} 但遇到 {ch}（开在 L{ln}）")
    for op, ln in stack:
        errors.append(f"{os.path.basename(path)}:{ln} 未闭合的 {op}")
    return errors


def main():
    problems = []
    swift_files = []
    web_files = []

    for dirpath, _, files in os.walk(APP):
        for fn in files:
            p = os.path.join(dirpath, fn)
            if fn.endswith(".swift"):
                swift_files.append(p)
            elif fn.endswith((".js", ".css")):
                web_files.append(p)

    print(f"Swift 文件 {len(swift_files)} 个，前端资源 {len(web_files)} 个\n")

    # 1) 括号平衡
    for p in swift_files + web_files:
        errs = check_balance(p)
        if errs:
            problems.extend(errs)
        else:
            print(f"  [平衡] OK  {os.path.basename(p)}")

    print()

    # 2) import 检查
    for p in swift_files:
        with open(p, "r", encoding="utf-8") as f:
            src = f.read()
        if not re.search(r"^\s*import\s+", src, re.M):
            problems.append(f"{os.path.basename(p)} 缺少 import")

    # 3) body 重名检查：同一个 View 里只能有一个 body
    #    多个 struct 各自有 body 是正常的，所以按 ": View" 声明数做上界比较
    for p in swift_files:
        with open(p, "r", encoding="utf-8") as f:
            src = strip_code(f.read())
        if re.search(r"\blet\s+body\s*:", src):
            problems.append(f"{os.path.basename(p)} 出现 `let body:` —— 与 SwiftUI 的 body 冲突")
        # 只统计真正的协议遵循声明 `: View {` / `: App {`，排除泛型约束 `Content: View`
        view_decls = re.findall(r":\s*(?:View|App)\s*\{", src)
        body_decls = re.findall(r"\bvar\s+body\b", src)
        print(f"  {os.path.basename(p):24s} View 声明 {len(view_decls)} 个 / body {len(body_decls)} 个")
        if len(body_decls) > len(view_decls):
            problems.append(
                f"{os.path.basename(p)} body 数({len(body_decls)}) 多于 View 声明数({len(view_decls)})")

    # 4) Theme 成员引用检查
    theme_path = os.path.join(APP, "RootView.swift")
    with open(theme_path, "r", encoding="utf-8") as f:
        theme_src = f.read()
    defined = set(re.findall(r"static\s+let\s+(\w+)\s*=", theme_src))
    print(f"  Theme 已定义: {sorted(defined)}")
    used = set()
    for p in swift_files:
        with open(p, "r", encoding="utf-8") as f:
            used |= set(re.findall(r"\bTheme\.(\w+)", f.read()))
    missing = used - defined
    if missing:
        problems.append(f"Theme 引用了不存在的成员: {sorted(missing)}")
    print(f"  Theme 被引用: {sorted(used)}\n")

    # 5) 关键符号是否被真正定义
    must_define = {
        "WebController": "class WebController",
        "AppSettings": "class AppSettings",
        "ScriptInjector": "enum ScriptInjector",
        "RootView": "struct RootView",
        "SettingsView": "struct SettingsView",
        "WebViewHost": "struct WebViewHost",
    }
    all_src = ""
    for p in swift_files:
        with open(p, "r", encoding="utf-8") as f:
            all_src += f.read() + "\n"
    for name, pattern in must_define.items():
        if pattern not in all_src:
            problems.append(f"缺少定义: {name}（期望 `{pattern}`）")

    # 6) Info.plist 存在
    if not os.path.isfile(os.path.join(APP, "Info.plist")):
        problems.append("缺少 Info.plist")

    # 7) AppIcon 存在
    icon = os.path.join(APP, "Assets.xcassets", "AppIcon.appiconset", "AppIcon-1024.png")
    if not os.path.isfile(icon):
        problems.append("缺少 AppIcon-1024.png")

    print("=" * 60)
    if problems:
        print(f"发现 {len(problems)} 个问题：")
        for x in problems:
            print("  !! " + x)
        sys.exit(1)
    print("✓ 静态自检全部通过")


if __name__ == "__main__":
    main()
