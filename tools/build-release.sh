#!/bin/sh
# 从 modules/ 重新打包全部 Magisk 模块，输出到 dist/ 并生成 SHA256SUMS。
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DIST="$ROOT/dist"
rm -rf "$DIST"
mkdir -p "$DIST"

pack() {
  id=$1
  out=$2
  dir="$ROOT/modules/$id"
  [ -f "$dir/module.prop" ] || { echo "缺少 $dir/module.prop" >&2; exit 1; }
  ( cd "$dir" && zip -q -r -X "$DIST/$out" . \
      -x '*.DS_Store' -x '__MACOSX/*' -x '*.idsig' )
  echo "打包 $out"
}

pack 901si_gsi_fixes   901si-gsi-fixes-v1.0.zip
pack lis2ds12_int      lis2ds12_int-v1.3.zip
pack ledlineage        ledlineage-v1.0.zip
pack stockcam_helpers  stockcam_helpers-v1.0.zip
pack volte_caf         volte_caf-v0.1.zip

( cd "$DIST" && shasum -a 256 *.zip > SHA256SUMS )
echo "---"
cat "$DIST/SHA256SUMS"
