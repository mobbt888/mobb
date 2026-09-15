#!/bin/bash
#
# 诊断 Info.plist 未被使用：真实 build 一个 app，打印最终 Info.plist 内容
# 云端调试用，定位到问题后可删除。
#
set +e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

rm -rf .probe2
mkdir -p .probe2/app

echo "===== pbxproj 里的 plist 相关设置 ====="
xcodegen generate -s project.yml -p .probe2/app -r . >/dev/null 2>&1
grep -E "GENERATE_INFOPLIST_FILE|INFOPLIST_FILE|INFOPLIST_KEY|COPY_INFOPLIST" .probe2/app/CloudPhone.xcodeproj/project.pbxproj | sed 's/^\s*//' | sort | uniq -c

echo ""
echo "===== target build settings ====="
cd .probe2/app
xcodebuild -project CloudPhone.xcodeproj -scheme CloudPhone -configuration Release -sdk iphoneos \
  -showBuildSettings 2>/dev/null | grep -iE "GENERATE_INFOPLIST_FILE|INFOPLIST_FILE|INFOPLIST_KEY|INFOPLIST_OUTPUT" | sed 's/^\s*//' | sort

echo ""
echo "===== 真实 build ====="
xcodebuild -project CloudPhone.xcodeproj -scheme CloudPhone -configuration Release -sdk iphoneos \
  -derivedDataPath dd -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  AD_HOC_CODE_SIGNING_ALLOWED=YES SKIP_INSTALL=NO build 2>&1 | tail -3

echo ""
echo "===== 产物 app 内容 ====="
ls -la dd/Build/Products/Release-iphoneos/CloudPhone.app

echo ""
echo "===== 最终 Info.plist ====="
plutil -p dd/Build/Products/Release-iphoneos/CloudPhone.app/Info.plist

echo ""
echo "===== 源文件 Info.plist 是否参与 copy ====="
cd "$ROOT"
grep -c "Info.plist" .probe2/app/CloudPhone.xcodeproj/project.pbxproj

echo ""
echo "=== done ==="
exit 0
