#!/system/bin/sh
MODDIR=${0%/*}
S=/sys/bus/i2c/devices/1-001d
LOG=/data/local/tmp/lis2ds12_int.log
log(){ echo "$(date '+%m-%d %H:%M:%S') $*" >> $LOG; }

log "服务启动 v1.3（CTRL4 脉冲型数据就绪中断）"
sleep 2

if [ -f /data/local/tmp/lis2ds12_off ]; then
  log "检测到 OFF 开关 -> 不写寄存器，退出"
  exit 0
fi

while true; do
  if [ -f /data/local/tmp/lis2ds12_off ]; then
    log "OFF 开关出现 -> 停止写入，退出"
    exit 0
  fi
  e=$(cat $S/enable 2>/dev/null)
  if [ "$e" = "1" ]; then
    echo 0x23 > $S/reg_addr 2>/dev/null
    v=$(cat $S/reg_value 2>/dev/null)
    if [ "$v" != "0x01" ]; then
      echo 0x23 > $S/reg_addr 2>/dev/null
      echo 1 > $S/reg_value 2>/dev/null
      log "enable=1 reg0x23=$v -> 0x01"
    fi
  fi
  sleep 1
done
