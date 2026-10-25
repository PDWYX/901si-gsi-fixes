#!/system/bin/sh
# 把厂商灯 HAL 写入的亮度值（0..255）翻译成这颗驱动认的 pattern 值
# （0 = 灭，1 = 常亮）。
#
# slg4ax42959v 驱动用 "poweron" 节点给所有通道做总闸：
# poweron=0 时 red/green/blue pattern 写得进去但灯不亮。
# 所以这里强制 poweron=1，只改三个通道的 pattern 节点。
# 绝对不要写 trigger/ 或全局 brightness —— 在这台机器上会直接内核崩溃。
L=/sys/class/leds
DRV=/sys/devices/soc/78b8000.i2c/i2c-4/4-0008/leds/slg4ax42959v_led

pval() { tr -cd '0-9' < "$1" 2>/dev/null; }
setled() {
  case "$1" in
    red)   echo "$2" > "$DRV/redled"   2>/dev/null ;;
    green) echo "$2" > "$DRV/greenled" 2>/dev/null ;;
    blue)  echo "$2" > "$DRV/blueled"  2>/dev/null ;;
  esac
}

# 等控制器上电（此时驱动节点已经存在）
i=0
while [ $i -lt 60 ]; do
  [ "$(pval "$DRV/poweron")" = "1" ] && break
  echo 1 > "$DRV/poweron" 2>/dev/null
  sleep 1
  i=$((i+1))
done

# 驱动默认会把绿灯置 1（开机一直亮绿灯），先从已知的“全灭”状态开始
setled red 0
setled green 0
setled blue 0

prev_red=0; prev_green=0; prev_blue=0
while :; do
  # 芯片空闲时驱动可能把 poweron 掉回 0，持续托住
  [ "$(pval "$DRV/poweron")" = "1" ] || echo 1 > "$DRV/poweron" 2>/dev/null

  for c in red green blue; do
    raw=$(cat "$L/$c/brightness" 2>/dev/null)
    # HAL 打开这些文件时没有 O_TRUNC，较短的新值可能留下旧尾巴
    # （"255\n" -> "0\n5"）：只取开头连续的数字。
    num=${raw%%[!0-9]*}
    case "$num" in ''|*[!0-9]*) continue ;; esac   # 还没有可用值
    if [ "$num" -gt 0 ]; then s=1; else s=0; fi
    eval "p=\$prev_$c"
    if [ "$s" != "$p" ]; then
      setled "$c" "$s"
      eval "prev_$c=$s"
    fi
  done
  sleep 0.15
done
