#!/bin/sh
# 从 apk-src/ 重新编译两个相机辅助 APK。
#
# 需要 Android SDK（build-tools + platforms/android-28）：
#   ANDROID_HOME=/path/to/sdk tools/build-apks.sh
# 可选签名参数：KEYSTORE / KS_PASS / KEY_ALIAS / KEY_PASS
# 未提供时在 build/ 生成一个本地测试密钥。
#
# 注意：模块里预置的 APK 用 CN=dsh 旧证书签名，方便在已安装设备上
# pm install -r 覆盖；重新签名会让覆盖安装因签名不一致而失败。
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SDK=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
[ -n "$SDK" ] || { echo "请设置 ANDROID_HOME" >&2; exit 1; }
[ -f "$SDK/platforms/android-28/android.jar" ] || { echo "缺少 platforms/android-28" >&2; exit 1; }
BT=$(ls -d "$SDK"/build-tools/* 2>/dev/null | sort -V | tail -1)
[ -n "$BT" ] || { echo "缺少 build-tools" >&2; exit 1; }
AJ="$SDK/platforms/android-28/android.jar"

KS=${KEYSTORE:-$ROOT/build/local.keystore}
KS_PASS=${KS_PASS:-android}
KEY_ALIAS=${KEY_ALIAS:-local}
KEY_PASS=${KEY_PASS:-android}
if [ ! -f "$KS" ]; then
  mkdir -p "$(dirname "$KS")"
  keytool -genkeypair -keystore "$KS" -storepass "$KS_PASS" -keypass "$KEY_PASS" \
    -alias "$KEY_ALIAS" -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=PDWYX" >/dev/null 2>&1
  echo "已生成本地测试密钥：$KS"
fi

build() {
  name=$1
  src="$ROOT/apk-src/$name"
  out="$ROOT/build/$name"
  rm -rf "$out"
  mkdir -p "$out/classes" "$out/dex"
  find "$src/src" -name '*.java' > "$out/sources.txt"
  javac -source 1.8 -target 1.8 -bootclasspath "$AJ" -d "$out/classes" @"$out/sources.txt"
  "$BT/d8" --min-api 21 --lib "$AJ" --output "$out/dex" $(find "$out/classes" -name '*.class')
  "$BT/aapt" package -f -M "$src/AndroidManifest.xml" -I "$AJ" -F "$out/unsigned.apk"
  ( cd "$out/dex" && zip -q -u ../unsigned.apk classes.dex )
  "$BT/zipalign" -f 4 "$out/unsigned.apk" "$out/aligned.apk"
  "$BT/apksigner" sign --ks "$KS" --ks-pass "pass:$KS_PASS" \
    --key-pass "pass:$KEY_PASS" --ks-key-alias "$KEY_ALIAS" \
    --out "$ROOT/build/$name.apk" "$out/aligned.apk"
  echo "生成 build/$name.apk"
}

build eventlogstub
build gallerybridge
