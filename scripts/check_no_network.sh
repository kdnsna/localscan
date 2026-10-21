#!/usr/bin/env bash
# 静态无网络检查：App 源码、entitlements 和 project.yml 都不得出现网络 API。
#
# 用法：
#   scripts/check_no_network.sh [仓库根目录]
#
# 默认检查脚本所在仓库；测试脚本会传入临时目录。命中时打印
# “文件:行号:内容”并以 1 退出，否则打印 OK 并以 0 退出。
set -uo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=${1:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}

if [ ! -d "$ROOT" ]; then
  echo "ERROR: 目录不存在: $ROOT" >&2
  exit 2
fi

status=0

# 单个 .swift 文件：跳过整行 // 注释后匹配网络相关符号。
check_swift_file() {
  local file=$1
  awk -v path="$file" '
    BEGIN {
      pattern = "URLSession|URLRequest|NWConnection|NWPathMonitor|NWListener|import[[:space:]]+Network|CFNetwork|CFStream|WKWebView|import[[:space:]]+WebKit|Socket[(]|getaddrinfo|http://|https://"
      found = 0
    }
    {
      line = $0
      trimmed = line
      sub(/^[[:space:]]+/, "", trimmed)
      if (trimmed ~ /^\/\//) {
        next
      }
      if (line ~ pattern) {
        printf "%s:%d:%s\n", path, NR, line
        found = 1
      }
    }
    END { exit found ? 1 : 0 }
  ' "$file" || status=1
}

if [ -d "$ROOT/LocalScan" ]; then
  while IFS= read -r -d '' file; do
    check_swift_file "$file"
  done < <(find "$ROOT/LocalScan" -type f -name '*.swift' -print0)
fi

# entitlements：任何 *.entitlements 都检查（不限于 LocalScan/）。
while IFS= read -r -d '' file; do
  if matches=$(grep -inE 'network|com\.apple\.developer\.networking|NSAppTransportSecurity|NSAllowsArbitraryLoads' "$file"); then
    while IFS= read -r line; do
      printf '%s:%s\n' "$file" "$line"
    done <<< "$matches"
    status=1
  fi
done < <(find "$ROOT" -type f -name '*.entitlements' -not -path '*/.git/*' -print0)

if [ -f "$ROOT/project.yml" ]; then
  if matches=$(grep -inE 'network|com\.apple\.developer\.networking|NSAppTransportSecurity|NSAllowsArbitraryLoads' "$ROOT/project.yml"); then
    while IFS= read -r line; do
      printf '%s:%s\n' "$ROOT/project.yml" "$line"
    done <<< "$matches"
    status=1
  fi
fi

if [ "$status" -eq 0 ]; then
  echo "OK: 未发现网络 API、网络 entitlement 或 ATS 配置"
else
  echo "FAIL: 发现网络相关代码/配置，LocalScan 必须完全离线" >&2
fi

exit "$status"
