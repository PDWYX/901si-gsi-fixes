#!/system/bin/sh
# Lineage 状态灯桥接：给厂商灯 HAL（lights.msm8909.so）补齐它写死的
# /sys/class/leds/{red,green,blue}/brightness 路径（本机没有这些路径），
# 并放行 HAL 写入。
L=/sys/class/leds
DRV=/sys/devices/soc/78b8000.i2c/i2c-4/4-0008/leds/slg4ax42959v_led
LOG=/data/adb/ledlineage
mkdir -p "$LOG"
exec >>"$LOG/boot.log" 2>&1
echo "=== $(date) post-fs-data"

[ -d "$L" ] || { echo "no $L"; exit 0; }
mountpoint -q "$L" && { echo "already a mountpoint, skip"; exit 0; }

# 1) 记下每个既有条目的真实路径
: > "$LOG/map"
for e in $(ls "$L"); do
  case "$e" in red|green|blue) continue;; esac
  p=$(readlink -f "$L/$e" 2>/dev/null)
  [ -n "$p" ] && [ -d "$p" ] && echo "$e $p" >> "$LOG/map"
done
echo "map:"; cat "$LOG/map"

# 2) 用 tmpfs 覆盖 /sys/class/leds，再把原有条目 bind mount 回去
mount -t tmpfs tmpfs "$L" || { echo "tmpfs mount failed"; exit 0; }
while read -r e p; do
  mkdir -p "$L/$e"
  mount --bind "$p" "$L/$e" || echo "bind $e failed"
done < "$LOG/map"

# 3) 建立厂商 HAL 会写入的兼容节点
for c in red green blue; do
  mkdir -p "$L/$c"
  for f in brightness blink breath delay_on delay_off; do
    : > "$L/$c/$f"
    chmod 666 "$L/$c/$f"
  done
  chmod 777 "$L/$c"
done

# 4) 安全阀：屏幕背光路径没保住就立刻回滚
if ! cat "$L/lcd-backlight/brightness" >/dev/null 2>&1; then
  echo "backlight missing after overlay -> rolling back"
  umount "$L" 2>/dev/null
  exit 0
fi
echo "overlay ok, backlight=$(cat "$L/lcd-backlight/brightness")"

# 5) 让 hal_light_default 能读写 tmpfs 节点
MP=""
for c in /data/adb/magisk/magiskpolicy /sbin/magiskpolicy magiskpolicy /debug_ramdisk/magiskpolicy; do
  [ -x "$c" ] && MP="$c" && break
done
if [ -n "$MP" ]; then
  "$MP" --live 'allow hal_light_default tmpfs file write' 2>&1
  "$MP" --live 'allow hal_light_default tmpfs file read' 2>&1
  "$MP" --live 'allow hal_light_default tmpfs dir search' 2>&1
else
  echo "magiskpolicy not found"
fi
# 6) 尽早压掉驱动开机默认的绿灯：先把三路 pattern 清零，再开总闸。
# 灯控驱动在 probe 时会把 green 置 1，这一步越早，开机亮绿灯的窗口越短。
echo "before clear: $(cat "$DRV/redled" 2>/dev/null) $(cat "$DRV/greenled" 2>/dev/null)"
for c in redled greenled blueled; do echo 0 > "$DRV/$c" 2>/dev/null; done
echo 1 > "$DRV/poweron" 2>/dev/null
echo "state: $(cat "$DRV/greenled" 2>/dev/null) $(cat "$DRV/redled" 2>/dev/null)"
