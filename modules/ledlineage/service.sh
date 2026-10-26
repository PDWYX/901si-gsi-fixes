#!/system/bin/sh
# 守护“亮度 -> pattern”翻译进程。
# 注意：Magisk 复制文件时不会保留可执行位，所以用 sh 显式执行，
# 并自行定位模块目录，不依赖 -x。
LOG=/data/adb/ledlineage
mkdir -p "$LOG"
exec >>"$LOG/boot.log" 2>&1

# 不再等 sys.boot_completed：守护本身只做"读亮度 -> 写 pattern"，
# 早启动就能早一步把驱动开机默认亮起的绿灯压掉。

D=""
for p in /data/adb/modules/ledlineage /data/adb/modules_update/ledlineage; do
  if [ -f "$p/daemon.sh" ]; then D="$p/daemon.sh"; break; fi
done
if [ -z "$D" ]; then
  echo "$(date) daemon.sh not found"
  exit 0
fi

echo "$(date) supervising $D (uptime $(cut -d' ' -f1 /proc/uptime))"
(
  while true; do
    sh "$D"
    echo "$(date) daemon exited, restarting in 3s"
    sleep 3
  done
) &
