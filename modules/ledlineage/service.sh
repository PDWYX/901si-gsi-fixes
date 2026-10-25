#!/system/bin/sh
# 等待开机完成，然后守护“亮度 -> pattern”翻译进程。
# 注意：Magisk 复制文件时不会保留可执行位，所以用 sh 显式执行，
# 并自行定位模块目录，不依赖 -x。
LOG=/data/adb/ledlineage
mkdir -p "$LOG"
exec >>"$LOG/boot.log" 2>&1

i=0
while [ "$(getprop sys.boot_completed)" != "1" ]; do
  i=$((i+1)); [ $i -gt 180 ] && break
  sleep 1
done
sleep 5

D=""
for p in /data/adb/modules/ledlineage /data/adb/modules_update/ledlineage; do
  if [ -f "$p/daemon.sh" ]; then D="$p/daemon.sh"; break; fi
done
if [ -z "$D" ]; then
  echo "$(date) 找不到 daemon.sh"
  exit 0
fi

echo "$(date) 守护 $D"
(
  while true; do
    sh "$D"
    echo "$(date) daemon 退出，3 秒后重启"
    sleep 3
  done
) &
