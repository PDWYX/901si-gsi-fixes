#!/system/bin/sh
# ledlineage v1.2 —— 低耗电、快速压掉开机绿灯的守护
#
# 作用：把厂商灯 HAL 写进 /sys/class/leds/{red,green,blue}/brightness 的 0..255
# 亮度，翻译成 slg4ax42959v 驱动认的 pattern 值（0 = 灭，1 = 常亮），
# 并把总闸 poweron 托住为 1。
#
# v1.1 相对 v1.0：不再 fork 任何子进程，轮询从 0.15s 放宽到 0.4s；
# 读文件用 shell 内建的 read 加输入重定向，写文件用内建的 echo，
# 解析用参数展开 —— 全程零 fork。
# v1.2 相对 v1.1：轮询收紧到 0.25s，且开机前 200 轮（约 50 秒）无条件回写 pattern，
# 把驱动 probe 时默认点亮的绿灯尽快压掉。
#
# 绝不写 .../slg4ax42959v_led/trigger 或全局 .../slg4ax42959v_led/brightness：
# 在这台机器上会让内核崩溃重启（实测两次）。

# 路径可用环境变量覆盖，便于在电脑上用假目录离线验证逻辑
L=${LED_L:-/sys/class/leds}
DRV=${LED_DRV:-/sys/devices/soc/78b8000.i2c/i2c-4/4-0008/leds/slg4ax42959v_led}

# 等控制器上电（最多 60 秒），把 poweron 托到 1
i=0
while [ $i -lt 60 ]; do
  p=''
  read -r p 2>/dev/null < "$DRV/poweron"
  [ "$p" = "1" ] && break
  echo 1 > "$DRV/poweron" 2>/dev/null
  sleep 1
  i=$((i+1))
done

# 驱动开机默认把绿灯置 1（"一直亮绿灯"），先清零，交给框架驱动
echo 0 > "$DRV/redled"   2>/dev/null
echo 0 > "$DRV/greenled" 2>/dev/null
echo 0 > "$DRV/blueled"  2>/dev/null

prev_red=0
prev_green=0
prev_blue=0
n=0

while :; do
  n=$((n+1))
  # 芯片空闲时驱动可能把 poweron 掉回 0，每 3 轮（约 1.2 秒）检查一次
  if [ $((n % 3)) -eq 1 ]; then
    p=''
    read -r p 2>/dev/null < "$DRV/poweron"
    [ "$p" = "1" ] || echo 1 > "$DRV/poweron" 2>/dev/null
  fi

  for c in red green blue; do
    v=''
    read -r v 2>/dev/null < "$L/$c/brightness"
    # HAL 打开这些文件时没有 O_TRUNC，较短的新值会留下旧尾巴
    # （"255" 被 "0" 覆盖后读出来是 "0" 换行 "5"）：只取开头连续的数字
    num=${v%%[!0-9]*}
    case "$num" in ''|*[!0-9]*) continue ;; esac
    if [ "$num" -gt 0 ]; then s=1; else s=0; fi
    eval "p=\$prev_$c"
    # 前 200 轮（约 50 秒）无条件回写：驱动上电时可能又把绿灯置 1，
    # 这一步负责把"开机残留的绿灯"立刻压掉，不依赖 HAL 是否写过。
    if [ $n -le 200 ] || [ "$s" != "$p" ]; then
      echo "$s" > "$DRV/${c}led" 2>/dev/null
      eval "prev_$c=$s"
    fi
  done

  sleep 0.25
done
