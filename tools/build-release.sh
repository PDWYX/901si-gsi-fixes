#!/bin/sh
# 从 modules/ 重新打包全部 Magisk 模块，输出到 dist/ 并生成 SHA256SUMS。
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DIST="$ROOT/dist"
rm -rf "$DIST"
mkdir -p "$DIST"

pack() {
  id=$1
  name=$2
  dir="$ROOT/modules/$id"
  [ -f "$dir/module.prop" ] || { echo "缺少 $dir/module.prop" >&2; exit 1; }
  ver=$(sed -n 's/^version=//p' "$dir/module.prop" | head -n 1)
  [ -n "$ver" ] || { echo "$dir/module.prop 缺少 version=" >&2; exit 1; }
  out="$name-$ver.zip"
  ( cd "$dir" && zip -q -r -X "$DIST/$out" . \
      -x '*.DS_Store' -x '__MACOSX/*' -x '*.idsig' )
  echo "打包 $out"
}

pack 901si_gsi_fixes   901si-gsi-fixes
pack lis2ds12_int      lis2ds12_int
pack ledlineage        ledlineage
pack stockcam_helpers  stockcam_helpers
pack volte_caf         volte_caf

( cd "$DIST" && shasum -a 256 *.zip > SHA256SUMS )
echo "---"
cat "$DIST/SHA256SUMS"
