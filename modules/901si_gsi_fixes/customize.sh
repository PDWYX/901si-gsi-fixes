#!/system/bin/sh
# 校验：JPEG HAL 补丁只对应一个确切的 vendor 库版本。
# 接受原厂版本或已经打过补丁的版本（例如在本模块之上重装），
# 其它版本一律拒绝，避免把相机 HAL 弄坏。
EXPECT=73d3594e71ed0866194ecaab845b781b
PATCHED=d6911e58ee5a2b2146022041152066b6
CUR=$(md5sum /vendor/lib/libmmqjpeg_codec.so 2>/dev/null | awk '{print $1}')

ui_print " "
ui_print "- 901si GSI 修复 v1.0"
case "$CUR" in
  "$EXPECT")
    ui_print "- 相机 JPEG 库版本匹配，安装补丁"
    ;;
  "$PATCHED")
    ui_print "- 相机 JPEG 库已是打过补丁的版本，继续安装"
    ;;
  *)
    ui_print "! /vendor/lib/libmmqjpeg_codec.so 版本不匹配"
    ui_print "!   期望: $EXPECT"
    ui_print "!   实际: ${CUR:-无法读取}"
    ui_print "! 已跳过相机 JPEG 补丁，仅安装两个属性修复。"
    [ -n "$MODPATH" ] && rm -rf "$MODPATH/system"
    ;;
esac
ui_print "- 安装完成，重启后生效"
