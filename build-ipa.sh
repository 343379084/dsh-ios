#!/usr/bin/env bash
# 在有 macOS + Xcode 的机器上本地出 unsigned IPA。
# 用法：./build-ipa.sh
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "需要 macOS + Xcode（xcodebuild 不在 PATH）" >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "缺少 xcodegen，正在尝试安装：brew install xcodegen" >&2
  command -v brew >/dev/null 2>&1 || { echo "也没有 brew，请先装 Homebrew 或手动装 XcodeGen" >&2; exit 1; }
  brew install xcodegen
fi

echo "==> 生成工程"
rm -rf DSHMobile.xcodeproj
xcodegen generate

echo "==> 编译（不签名）"
rm -rf build
set -o pipefail
xcodebuild \
  -project DSHMobile.xcodeproj \
  -scheme DSHMobile \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  DEVELOPMENT_TEAM="" \
  build 2>&1 | tee build.log

echo "==> 打包"
APP=$(find build/Build/Products/Release-iphoneos -maxdepth 1 -name "*.app" -print -quit)
if [ -z "$APP" ]; then echo "没有产出 .app" >&2; exit 1; fi

rm -rf Payload DSHMobile-unsigned.ipa
mkdir -p Payload
cp -R "$APP" Payload/
rm -rf Payload/*.app/_CodeSignature || true
rm -rf Payload/*.app/embedded.mobileprovision || true
/usr/bin/zip -qry DSHMobile-unsigned.ipa Payload

echo
echo "✓ 完成：$(pwd)/DSHMobile-unsigned.ipa  ($(du -h DSHMobile-unsigned.ipa | cut -f1))"
echo "  下一步：用 Sideloadly / AltStore / TrollStore 自签后安装"
