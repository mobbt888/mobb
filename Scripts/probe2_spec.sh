#!/bin/bash
#
# 诊断 Info.plist 未被使用的问题：对比三种写法的实际 build settings
# 云端调试用，定位到问题后可删除。
#
set +e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

rm -rf .probe2
mkdir -p .probe2

dump() {
  local name="$1"
  local spec="$2"
  echo "===== VARIANT $name ====="
  mkdir -p ".probe2/$name"
  if ! xcodegen generate -s "$spec" -p ".probe2/$name" -r . >/dev/null 2>&1; then
    echo "(xcodegen generate 失败)"
    return
  fi
  ( cd ".probe2/$name" && xcodebuild -target CloudPhone -configuration Release -sdk iphoneos -showBuildSettings 2>/dev/null ) \
    | grep -iE "GENERATE_INFOPLIST_FILE|INFOPLIST_FILE |INFOPLIST_KEY|PRODUCT_BUNDLE_IDENTIFIER|ASSETCATALOG" | sed 's/^ *//' | sort
  echo ""
}

# A: 当前配置（info.path + GENERATE_INFOPLIST_FILE=NO + INFOPLIST_FILE）
cp project.yml .probe2/A.yml
dump A .probe2/A.yml

# C: 去掉 info 段，只留 settings 里的 INFOPLIST_FILE + GENERATE_INFOPLIST_FILE=NO
sed '/^    info:$/,/^    entitlements:$/ { /^    entitlements:$/!d }' project.yml > .probe2/C.yml
dump C .probe2/C.yml

# B: 在 C 基础上再去掉 GENERATE_INFOPLIST_FILE
sed '/^    info:$/,/^    entitlements:$/ { /^    entitlements:$/!d }' project.yml \
  | grep -v "GENERATE_INFOPLIST_FILE" > .probe2/B.yml
dump B .probe2/B.yml

echo "=== diff A vs C ==="
diff .probe2/A.yml .probe2/C.yml
echo "=== diff C vs B ==="
diff .probe2/C.yml .probe2/B.yml

echo ""
echo "=== done ==="
exit 0
