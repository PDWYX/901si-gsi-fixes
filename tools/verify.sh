#!/bin/sh
# 在已连接的设备上检查各修复是否生效（需要 root / adb）。
#   tools/verify.sh [serial]
set -u
ADB="adb"
[ -n "${1:-}" ] && ADB="adb -s $1"
SH() { $ADB shell "su -c '$*'"; }

echo "== 属性"
SH getprop debug.hwui.use_buffer_age
SH getprop vendor.vidc.disable.split.mode
SH getprop persist.dbg.ims_volte_enable

echo "== 加速度计（应每秒约 50 次）"
SH "grep lis2ds12 /proc/interrupts; sleep 5; grep lis2ds12 /proc/interrupts"

echo "== 状态灯节点"
SH "ls /sys/class/leds/red /sys/class/leds/green 2>/dev/null"

echo "== IMS 注册（state: 2 为已注册）"
SH "dumpsys telephony.registry | grep -i ims | head"

echo "== 模块列表"
$ADB shell "ls /data/adb/modules"
