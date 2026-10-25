#!/system/bin/sh
MODDIR=${0%/*}
RP=""
for c in resetprop /sbin/resetprop /data/adb/magisk/resetprop /debug_ramdisk/resetprop; do
  if [ -x "$c" ] || command -v "$c" >/dev/null 2>&1; then RP="$c"; break; fi
done
[ -z "$RP" ] && exit 0
"$RP" persist.dbg.ims_volte_enable 1
"$RP" persist.dbg.volte_avail_ovr 1
"$RP" persist.dbg.vt_avail_ovr 1
"$RP" persist.dbg.wfc_avail_ovr 1
"$RP" persist.dbg.allow_ims_off 1
