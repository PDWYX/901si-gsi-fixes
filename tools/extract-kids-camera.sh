#!/bin/sh
# 从自己的原厂 system.img 里提取相机 APK（不随仓库分发）。
#   tools/extract-kids-camera.sh /path/to/system.img [输出目录]
set -eu

IMG=${1:?用法: $0 system.img [outdir]}
OUT=${2:-.}
mkdir -p "$OUT"

if ! command -v debugfs >/dev/null 2>&1; then
  echo "需要 e2fsprogs 的 debugfs" >&2
  exit 1
fi

debugfs -R "dump /app/KidsCamera/KidsCamera.apk $OUT/KidsCamera.apk" "$IMG"
ls -l "$OUT/KidsCamera.apk"
echo "安装：adb install -r $OUT/KidsCamera.apk"
