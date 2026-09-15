#!/bin/bash
#
# 打包 ipa（两种模式）
#
#   1) 未签名包：产出 iPhone/真机能用的 Payload 结构 ipa，交给第三方工具或自己的证书重签
#        bash Scripts/build_ipa.sh unsigned
#
#   2) 已签名包：需要 Apple 开发者账号 + Xcode 登录
#        DEVELOPMENT_TEAM=ABCDE12345 bash Scripts/build_ipa.sh development
#        DEVELOPMENT_TEAM=ABCDE12345 bash Scripts/build_ipa.sh ad-hoc
#        DEVELOPMENT_TEAM=ABCDE12345 bash Scripts/build_ipa.sh app-store
#
# 前置条件（macOS）：Xcode 15+；签名模式还需 brew install xcodegen 并登录开发者账号。
# unsigned 模式同样依赖 XcodeGen 生成工程。
#
# ⚠️ 本脚本必须是 LF 行尾。若在 Windows 上被改成 CRLF，先执行：
#      perl -pi -e 's/\r\n/\n/g' Scripts/build_ipa.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODE="${1:-${EXPORT_METHOD:-unsigned}}"
TEAM_ID="${DEVELOPMENT_TEAM:-XXXXXXXXXX}"
BUNDLE_ID="${PRODUCT_BUNDLE_IDENTIFIER:-com.js123.cloudphone}"

command -v xcodegen >/dev/null 2>&1 || {
  echo "❌ 缺少 xcodegen，请先执行：brew install xcodegen"
  exit 1
}

case "$(uname -s)" in
  Darwin) SED_INPLACE=(-i "") ;;
  *)      SED_INPLACE=(-i)   ;;
esac
sed "${SED_INPLACE[@]}" "s/PRODUCT_BUNDLE_IDENTIFIER: .*/PRODUCT_BUNDLE_IDENTIFIER: ${BUNDLE_ID}/" project.yml

mkdir -p build
rm -rf build/ipa build/*.ipa

if [[ "$MODE" == "unsigned" ]]; then

  echo "▶ 构建未签名 ipa（Bundle ID: ${BUNDLE_ID}）"
  rm -rf build/Build
  xcodegen generate --quiet

  xcodebuild \
    -project CloudPhone.xcodeproj \
    -scheme CloudPhone \
    -configuration Release \
    -sdk iphoneos \
    -derivedDataPath build \
    -destination 'generic/platform=iOS' \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    AD_HOC_CODE_SIGNING_ALLOWED=YES \
    SKIP_INSTALL=NO \
    build

  APP="build/Build/Products/Release-iphoneos/CloudPhone.app"
  [[ -d "$APP" ]] || {
    echo "❌ 产物缺失：$APP"
    exit 1
  }

  # Xcode 26 与 XcodeGen 2.46 组合下，INFOPLIST_FILE 的自动处理会把自定义键丢掉
  # （最终只剩 Xcode 自动生成的字段），所以构建后用工程自带的 plist 覆盖回去，
  # 顺带展开里面的 $(...) build setting 占位符。
  mkdir -p build/plist
  perl -pe "s/\\$\\(PRODUCT_BUNDLE_IDENTIFIER\\)/${BUNDLE_ID}/g; s/\\$\\(EXECUTABLE_NAME\\)/CloudPhone/g; s/\\$\\(PRODUCT_NAME\\)/CloudPhone/g" \
    Resources/Info.plist > build/plist/Info.plist
  cp build/plist/Info.plist "$APP/Info.plist"

  mkdir -p build/ipa/Payload
  cp -R "$APP" build/ipa/Payload/
  (cd build/ipa && zip -qry ../CloudPhone-unsigned.ipa Payload)

  echo ""
  echo "✅ 未签名包已生成：build/CloudPhone-unsigned.ipa"
  echo "   该包不能直接安装到未越狱设备，需先用你的证书重签，见 README「用你自己的证书重签」。"
  if [[ "$(uname -s)" == "Darwin" ]]; then open build; fi
  exit 0
fi

# ---------- 签名模式 ----------

if [[ "$TEAM_ID" == "XXXXXXXXXX" ]]; then
  echo "❌ 未设置 DEVELOPMENT_TEAM。"
  echo "   在 https://developer.apple.com/account 的 Membership 页可查到团队 ID。"
  echo "   用法：DEVELOPMENT_TEAM=ABCDE12345 bash Scripts/build_ipa.sh ${MODE}"
  exit 1
fi

case "$MODE" in
  development|ad-hoc|app-store) ;;
  *) echo "❌ 未知导出方式：$MODE（可选 unsigned / development / ad-hoc / app-store）"; exit 1 ;;
esac

sed "${SED_INPLACE[@]}" "s/DEVELOPMENT_TEAM: .*/DEVELOPMENT_TEAM: ${TEAM_ID}/" project.yml
sed -e "s/__TEAM_ID__/${TEAM_ID}/" -e "s/__METHOD__/${MODE}/" \
  ExportOptions.template.plist > build/ExportOptions.plist

echo "▶ 打包签名 ipa（方式: ${MODE}，Bundle ID: ${BUNDLE_ID}）"
rm -rf build/CloudPhone.xcarchive
xcodegen generate --quiet

xcodebuild \
  -project CloudPhone.xcodeproj \
  -scheme CloudPhone \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/CloudPhone.xcarchive \
  archive

xcodebuild \
  -exportArchive \
  -archivePath build/CloudPhone.xcarchive \
  -exportPath build/ipa \
  -exportOptionsPlist build/ExportOptions.plist \
  -allowProvisioningUpdates

IPA="$(find build/ipa -name '*.ipa' | head -n 1)"
echo ""
echo "✅ 打包完成：${IPA}"
if [[ "$(uname -s)" == "Darwin" && -n "$IPA" ]]; then open build/ipa; fi
