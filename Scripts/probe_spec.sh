#!/bin/bash
#
# 二分定位 XcodeGen 解析失败点（第二轮：聚焦 info 字段写法）
# 云端调试用，定位到问题后可删除。
#
set +e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

rm -rf .probe
mkdir -p .probe
echo "=== cwd: $(pwd)"
echo "=== xcodegen: $(xcodegen --version 2>&1)"

gen() {
  local name="$1"
  local spec="$2"
  echo ""
  echo "===== CASE $name ====="
  mkdir -p ".probe/$name"
  xcodegen generate -s "$spec" -p ".probe/$name" -r . 2>&1 | tail -4
  echo "exit=${PIPESTATUS[0]}"
}

# c10: info.properties 全平铺（无嵌套字典）
cat > .probe/c10.yml <<'EOF'
name: CloudPhone
options:
  deploymentTarget:
    iOS: "16.0"
targets:
  CloudPhone:
    type: application
    platform: iOS
    sources:
      - path: Sources
    info:
      properties:
        CFBundleDisplayName: test
        CFBundleDevelopmentRegion: zh_CN
        NSCameraUsageDescription: camera reason
EOF
gen c10 .probe/c10.yml

# c11: info.properties 含嵌套字典
cat > .probe/c11.yml <<'EOF'
name: CloudPhone
options:
  deploymentTarget:
    iOS: "16.0"
targets:
  CloudPhone:
    type: application
    platform: iOS
    sources:
      - path: Sources
    info:
      properties:
        UILaunchScreen:
          UIColorName: ""
EOF
gen c11 .probe/c11.yml

# c12: info.path 指向真实 plist
cat > .probe/c12.yml <<'EOF'
name: CloudPhone
options:
  deploymentTarget:
    iOS: "16.0"
targets:
  CloudPhone:
    type: application
    platform: iOS
    sources:
      - path: Sources
    info:
      path: Resources/Info.plist
EOF
gen c12 .probe/c12.yml

# c13: 完整替代方案 —— info.path + entitlements + Resources + settings + schemes
cat > .probe/c13.yml <<'EOF'
name: CloudPhone
options:
  deploymentTarget:
    iOS: "16.0"
  createIntermediateGroups: true
  groupSortPosition: none
settings:
  base:
    SWIFT_VERSION: "5.9"
    SDKROOT: iphoneos
    TARGETED_DEVICE_FAMILY: "1"
  configs:
    Debug:
      SWIFT_ACTIVE_COMPILATION_CONDITIONS: DEBUG
    Release:
      SWIFT_OPTIMIZATION_LEVEL: "-O"
targets:
  CloudPhone:
    type: application
    platform: iOS
    sources:
      - path: Sources
      - path: Resources
    info:
      path: Resources/Info.plist
    entitlements:
      path: Resources/CloudPhone.entitlements
      properties: {}
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.js123.cloudphone
        PRODUCT_NAME: CloudPhone
        MARKETING_VERSION: "1.0"
        CURRENT_PROJECT_VERSION: "1"
        CODE_SIGN_STYLE: Automatic
        INFOPLIST_KEY_UIApplicationSceneManifest_Generation: "YES"
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        IPHONEOS_DEPLOYMENT_TARGET: "16.0"
schemes:
  CloudPhone:
    build:
      targets:
        CloudPhone: all
    run:
      config: Debug
    archive:
      config: Release
EOF
gen c13 .probe/c13.yml

echo ""
echo "=== generated projects ==="
ls -la .probe

echo ""
echo "=== done ==="
exit 0
