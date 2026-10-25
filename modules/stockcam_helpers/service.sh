#!/system/bin/sh
# 等系统就绪
i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 180 ]; do
  sleep 2; i=$((i+1))
done
sleep 5
LOG=/data/adb/stockcam_helpers.log
say() { echo "$(date '+%H:%M:%S') $*" >> "$LOG"; }

MODDIR=${0%/*}
APKDIR="$MODDIR/apks"
CAM=pkg=jp.co.seiko.kidsphone

installed() { pm list packages 2>/dev/null | grep -q "^package:$1$"; }

# 1. 系统事件日志 provider 替身
if ! installed com.dsh.eventlogstub; then
  say "install eventlogstub"
  pm install -r "$APKDIR/eventlogstub.apk" >> "$LOG" 2>&1
else
  say "eventlogstub already installed"
fi

# 2. 相册转接（把 org.codeaurora.gallery 指到系统 Gallery2）
if ! installed org.codeaurora.gallery; then
  say "install gallerybridge"
  pm install -r "$APKDIR/gallerybridge.apk" >> "$LOG" 2>&1
else
  say "gallerybridge already installed"
fi

# 3. 相机 App 的运行权限（应用自己不会弹窗时会被拒）
if installed jp.co.seiko.kidsphone; then
  for p in android.permission.CAMERA android.permission.RECORD_AUDIO \
           android.permission.READ_EXTERNAL_STORAGE android.permission.WRITE_EXTERNAL_STORAGE; do
    # 开机早期从 magisk 域调 pm 偶尔返回 "Failed transaction"；dumpsys 里未授予就补授：
    # 先以 root 授一次，再以 shell(uid 2000) 授一次（shell 才持有 GRANT_RUNTIME_PERMISSIONS）
    granted() {
      dumpsys package jp.co.seiko.kidsphone 2>/dev/null \
        | grep -A20 "runtime permissions:" | grep -q "$1: granted=true"
    }
    granted "$p" && continue
    pm grant jp.co.seiko.kidsphone "$p" >> "$LOG" 2>&1
    granted "$p" && continue
    sleep 1
    su 2000 -c "pm grant jp.co.seiko.kidsphone $p" >> "$LOG" 2>&1
  done
  say "camera permissions checked"
fi
say "done"
