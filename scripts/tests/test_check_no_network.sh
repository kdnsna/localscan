#!/usr/bin/env bash
# 用临时目录里的干净/违规样例验证 check_no_network.sh 的退出码。
set -uo pipefail

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CHECK="$TEST_DIR/../check_no_network.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/localscan-no-network.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

passed=0
failed=0

assert_exit() {
  local expected=$1
  local root=$2
  local name=$3
  local output
  local code
  if output=$("$CHECK" "$root" 2>&1); then
    code=0
  else
    code=$?
  fi
  if [ "$code" -eq "$expected" ]; then
    passed=$((passed + 1))
    printf 'ok   %s (exit %s)\n' "$name" "$code"
  else
    failed=$((failed + 1))
    printf 'FAIL %s: 期望 exit %s，实际 exit %s\n%s\n' \
      "$name" "$expected" "$code" "$output" >&2
  fi
}

# 1) 干净样例：整行注释里的网络 API 必须被忽略。
mkdir -p "$WORK/clean/LocalScan"
cat > "$WORK/clean/LocalScan/Clean.swift" <<'SWIFT'
// URLSession / https://example.invalid 在整行注释里，不应命中。
import Foundation

let message = "LocalScan stays local"
SWIFT
cat > "$WORK/clean/project.yml" <<'YAML'
name: Clean
settings:
  base:
    SWIFT_VERSION: "5.0"
YAML
assert_exit 0 "$WORK/clean" "clean project"

# 2) Swift 违规：真实使用 URLSession。
mkdir -p "$WORK/swift-violation/LocalScan"
cat > "$WORK/swift-violation/LocalScan/Bad.swift" <<'SWIFT'
import Foundation

func fetchSomething() {
  _ = URLSession.shared
}
SWIFT
assert_exit 1 "$WORK/swift-violation" "URLSession in Swift"

# 3) 项目配置违规：ATS 放开任意加载。
mkdir -p "$WORK/project-violation/LocalScan"
cat > "$WORK/project-violation/LocalScan/Clean.swift" <<'SWIFT'
import Foundation
SWIFT
cat > "$WORK/project-violation/project.yml" <<'YAML'
name: Bad
settings:
  base:
    NSAppTransportSecurity:
      NSAllowsArbitraryLoads: true
YAML
assert_exit 1 "$WORK/project-violation" "ATS in project.yml"

# 4) entitlements 违规：网络客户端 entitlement。
mkdir -p "$WORK/entitlement-violation/LocalScan"
cat > "$WORK/entitlement-violation/LocalScan/Clean.swift" <<'SWIFT'
import Foundation
SWIFT
cat > "$WORK/entitlement-violation/LocalScan.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>com.apple.developer.networking.wifi-info</key>
  <true/>
</dict>
</plist>
PLIST
assert_exit 1 "$WORK/entitlement-violation" "networking entitlement"

# 5) 注释里的 http:// 不命中，getaddrinfo 命中。
mkdir -p "$WORK/swift-violation-2/LocalScan"
cat > "$WORK/swift-violation-2/LocalScan/Bad.swift" <<'SWIFT'
import Foundation

// let endpoint = "http://example.invalid"
let host = getaddrinfo
SWIFT
assert_exit 1 "$WORK/swift-violation-2" "getaddrinfo in Swift"

echo "通过 $passed 个样例，失败 $failed 个"
if [ "$failed" -ne 0 ]; then
  exit 1
fi
