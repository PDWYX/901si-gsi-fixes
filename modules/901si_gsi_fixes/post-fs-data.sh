#!/system/bin/sh
# 901si GSI 修复 —— 在 zygote / SystemUI / media 服务启动之前尽早执行。
MODDIR=${0%/*}

RP=""
for c in resetprop /sbin/resetprop /data/adb/magisk/resetprop /debug_ramdisk/resetprop; do
  if [ -x "$c" ] || command -v "$c" > /dev/null 2>&1; then RP="$c"; break; fi
done
[ -z "$RP" ] && exit 0

# 1) HWUI：Adreno 304 驱动声明了 EGL_KHR_partial_update，但回答
#    EGL_BUFFER_AGE_EXT 时给的值是错的，HWUI 因此会复用旧帧。
#    关掉“缓冲代龄”后，HWUI 回落到整帧保留。
"$RP" debug.hwui.use_buffer_age false

# 2) venus 解码器：Android 9 的 ACodec 会请求 DPB/OPB 分离模式，
#    而本机 8.1 固件没有实现；固件直接销毁会话，所有硬解失败。
#    强制回到经典的合并模式。
"$RP" vendor.vidc.disable.split.mode 1
