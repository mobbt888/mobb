#!/bin/bash
#
# 二分定位 XcodeGen 解析 project.yml 失败的字段。
# 云端调试用，定位到问题后可删除。
#
set +e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

mkdir -p .probe
echo "=== cwd: $(pwd)"
echo "=== xcodegen: $(xcodegen --version 2>&1)"

gen() {
  local name="$1"
  local spec="$2"
  echo ""
  echo "===== CASE $name ====="
  rm -rf ".probe/$name"
  mkdir -p ".probe/$name"
  xcodegen generate -s "$spec" -p ".probe/$name" 2>&1 | tail -4
  echo "exit=${PIPESTATUS[0]}"
}

# ---- c1: 最小 ----
cat > .probe/c1.yml <<'EOF'
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
EOF
gen c1 .probe/c1.yml

# ---- c2: + Resources ----
cat > .probe/c2.yml <<'EOF'
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
      - path: Resources
EOF
gen c2 .probe/c2.yml

# ---- c3: + entitlements ----
cat > .probe/c3.yml <<'EOF'
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
    entitlements:
      path: Resources/CloudPhone.entitlements
      properties: {}
EOF
gen c3 .probe/c3.yml

# ---- c4: + info properties ----
cat > .probe/c4.yml <<'EOF'
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
        UILaunchScreen:
          UIColorName: ""
EOF
gen c4 .probe/c4.yml

# ---- c5: + settings base ----
cat > .probe/c5.yml <<'EOF'
name: CloudPhone
targets:
  CloudPhone:
    type: application
    platform: iOS
    sources:
      - path: Sources
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.js123.cloudphone
        PRODUCT_NAME: CloudPhone
EOF
gen c5 .probe/c5.yml

# ---- c6: + options 全量 ----
cat > .probe/c6.yml <<'EOF'
name: CloudPhone
options:
  deploymentTarget:
    iOS: "16.0"
  createIntermediateGroups: true
  groupSortPosition: none
targets:
  CloudPhone:
    type: application
    platform: iOS
    sources:
      - path: Sources
EOF
gen c6 .probe/c6.yml

# ---- c7: + schemes ----
cat > .probe/c7.yml <<'EOF'
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
schemes:
  CloudPhone:
    build:
      targets:
        CloudPhone: all
EOF
gen c7 .probe/c7.yml

# ---- c8: 原始 project.yml ----
cp project.yml .probe/c8.yml
gen c8 .probe/c8.yml

echo ""
echo "=== done ==="
exit 0
