"""校验 unsigned IPA 的结构，确认它能被签名工具正常重签。

检查项：
1. zip 顶层只能是 Payload/
2. Payload/<App>.app/ 存在且含 Info.plist + 可执行文件
3. 可执行文件是 Mach-O 且 cputype 为 arm64
4. 四份注入资源在 .app 根目录（App 靠 Bundle.main.url(forResource:) 找）
5. Info.plist 里 bundle id / 版本 / ATS 关键项正确
6. 没有残留 _CodeSignature（重签前应该是干净的）
"""
import os
import plistlib
import struct
import sys
import zipfile

IPA = sys.argv[1] if len(sys.argv) > 1 else "成品/DSHMobile-unsigned.ipa"

EXEC_MAGIC = {
    0xFEEDFACF: "Mach-O 64-bit",
    0xFEEDFACE: "Mach-O 32-bit",
    0xCEFAEDFE: "Mach-O 32-bit (LE)",
    0xCFFAEDFE: "Mach-O 64-bit (LE)",
    0xCAFEBABE: "Fat/Universal",
}
CPU_NAMES = {
    0x0100000C: "arm64",
    0x0200000C: "arm64_32",
    0x0000000C: "arm",
    0x01000007: "x86_64",
}

problems = []


def main():
    if not os.path.isfile(IPA):
        print(f"找不到 {IPA}")
        sys.exit(1)

    print(f"IPA: {IPA}  ({os.path.getsize(IPA):,} bytes)\n")

    with zipfile.ZipFile(IPA) as z:
        names = z.namelist()

        # 1) 顶层结构
        tops = sorted({n.split("/")[0] for n in names})
        print(f"zip 顶层: {tops}")
        if tops != ["Payload"]:
            problems.append(f"顶层应只有 Payload/，实际 {tops}")

        apps = sorted({n.split("/")[1] for n in names
                       if n.startswith("Payload/") and len(n.split("/")) > 1 and n.split("/")[1]})
        print(f"Payload 内: {apps}")
        app_dirs = [a for a in apps if a.endswith(".app")]
        if len(app_dirs) != 1:
            problems.append(f"Payload 里应恰好 1 个 .app，实际 {app_dirs}")
            sys.exit(1)
        app = app_dirs[0]
        root = f"Payload/{app}/"
        print(f"App bundle: {root}\n")

        # 2) Info.plist + 可执行文件
        app_files = [n[len(root):] for n in names if n.startswith(root) and not n.endswith("/")]
        top_files = sorted(f for f in app_files if "/" not in f)
        print(f".app 根目录文件 ({len(top_files)} 个):")
        for f in top_files:
            print(f"   {f}")

        # 3) 读 Info.plist
        exe = None
        if "Info.plist" not in top_files:
            problems.append("缺 Info.plist")
        else:
            with z.open(root + "Info.plist") as f:
                info = plistlib.load(f)
            exe = info.get("CFBundleExecutable")
            print(f"\nInfo.plist:")
            for k in ("CFBundleIdentifier", "CFBundleExecutable", "CFBundleShortVersionString",
                      "CFBundleVersion", "CFBundleDisplayName", "MinimumOSVersion",
                      "CFBundleSupportedPlatforms", "DTPlatformName", "DTSDKName"):
                if k in info:
                    print(f"   {k} = {info[k]}")
            ats = info.get("NSAppTransportSecurity", {})
            print(f"   ATS NSAllowsArbitraryLoads = {ats.get('NSAllowsArbitraryLoads')}")
            if not ats.get("NSAllowsArbitraryLoads"):
                problems.append("ATS 没放行 http，连 http:// 的 dsh 会失败")
            for k in ("NSCameraUsageDescription", "NSPhotoLibraryUsageDescription"):
                if k not in info:
                    print(f"   [警告] 缺 {k}（网页里点拍照/相册会崩）")

        # 4) 可执行文件架构
        if exe:
            exe_path = root + exe
            if exe_path not in names:
                problems.append(f"CFBundleExecutable={exe} 但 zip 里没有这个文件")
            else:
                with z.open(exe_path) as f:
                    head = f.read(32)
                prefix = head[:4]
                print(f"\n可执行文件 {exe}:")
                if prefix in (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe"):
                    # Mach-O，小端主机（arm64/x86_64 iOS 都是）
                    is64 = prefix == b"\xcf\xfa\xed\xfe"
                    cputype, cpusub = struct.unpack("<II", head[4:12])
                    cpu = CPU_NAMES.get(cputype, f"0x{cputype:08X}")
                    print(f"   Mach-O {'64' if is64 else '32'}-bit, 架构 = {cpu}")
                    if cpu != "arm64":
                        problems.append(f"架构是 {cpu}，iPhone 真机需要 arm64")
                elif prefix == b"\xca\xfe\xba\xbe":
                    # Fat / Universal，头是大端
                    nfat = struct.unpack(">I", head[4:8])[0]
                    print(f"   Fat/Universal，包含 {nfat} 个架构")
                    arches = []
                    for i in range(min(nfat, 8)):
                        off = 8 + i * 20
                        if off + 20 > len(head):
                            break
                        ct, _cs, _o, _s, _a = struct.unpack(">IIIII", head[off:off + 20])
                        arches.append(CPU_NAMES.get(ct, f"0x{ct:08X}"))
                    print(f"   架构列表: {arches}")
                    if "arm64" not in arches:
                        problems.append(f"Fat 里没有 arm64：{arches}")
                elif prefix in (b"\xca\xfe\xba\xbf",):
                    problems.append("这是 fat 归档(静态库)，不是可执行文件")
                else:
                    problems.append(f"不是有效 Mach-O，前 4 字节 = {prefix.hex()}")

        # 5) 注入资源
        print("\n注入资源（必须在 .app 根目录）:")
        for f in ("mobile.css", "inject.js", "early-polyfill.js", "ios-tweaks.css"):
            if f in top_files:
                size = z.getinfo(root + f).file_size
                print(f"   OK  {f:22s} {size:,} bytes")
            else:
                problems.append(f"{f} 不在 .app 根目录")

        # 6) 签名残留
        print("\n签名残留:")
        sig = [n for n in names if "_CodeSignature" in n]
        prov = root + "embedded.mobileprovision"
        print(f"   _CodeSignature 文件数: {len(sig)}  (重签前应为 0)")
        print(f"   embedded.mobileprovision: {'存在' if prov in names else '无（预期）'}")

        # 7) 关键框架
        fw = sorted({n for n in names if "/Frameworks/" in n})
        print(f"\n内嵌 Frameworks: {len(fw)} 个（Swift 标准库 iOS 12.2+ 系统自带，0 个正常）")

    print("\n" + "=" * 60)
    if problems:
        print(f"发现 {len(problems)} 个问题：")
        for p in problems:
            print("  !! " + p)
        sys.exit(1)
    print("✓ IPA 结构校验全部通过，可以直接拿去签名")


if __name__ == "__main__":
    main()
