#!/bin/sh
# 重新编译 VoLTE 的 RRO 覆盖层（com.dsh.ims.overlay）。
# 预置在模块里的 ImsCafOverlay.apk 可以直接用，这个脚本只用于修改后重建。
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SDK=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
[ -n "$SDK" ] || { echo "请设置 ANDROID_HOME" >&2; exit 1; }
BT=$(ls -d "$SDK"/build-tools/* 2>/dev/null | sort -V | tail -1)
AJ="$SDK/platforms/android-28/android.jar"
OUT="$ROOT/build/overlay"
rm -rf "$OUT"; mkdir -p "$OUT"

"$BT/aapt" package -f -M "$ROOT/overlay-src/ims/AndroidManifest.xml" \
  -S "$ROOT/overlay-src/ims/res" -I "$AJ" -F "$OUT/unsigned.apk"
"$BT/zipalign" -f 4 "$OUT/unsigned.apk" "$OUT/aligned.apk"

KS=${KEYSTORE:-$ROOT/build/local.keystore}
KS_PASS=${KS_PASS:-android}
KEY_ALIAS=${KEY_ALIAS:-local}
KEY_PASS=${KEY_PASS:-android}
if [ ! -f "$KS" ]; then
  mkdir -p "$(dirname "$KS")"
  keytool -genkeypair -keystore "$KS" -storepass "$KS_PASS" -keypass "$KEY_PASS" \
    -alias "$KEY_ALIAS" -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=PDWYX" >/dev/null 2>&1
fi
"$BT/apksigner" sign --ks "$KS" --ks-pass "pass:$KS_PASS" \
  --key-pass "pass:$KEY_PASS" --ks-key-alias "$KEY_ALIAS" \
  --out "$ROOT/build/ImsCafOverlay.apk" "$OUT/aligned.apk"
echo "生成 build/ImsCafOverlay.apk"
