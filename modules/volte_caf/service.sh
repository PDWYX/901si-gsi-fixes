#!/system/bin/sh
MODDIR=${0%/*}
( until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 3; done
  sleep 8
  cmd overlay enable --user 0 com.dsh.ims.overlay 2>&1
  sleep 2
  if ! dumpsys overlay 2>/dev/null | grep -q "com.dsh.ims.overlay.*STATE_ENABLED"; then
    # fallback: toggle
    cmd overlay disable --user 0 com.dsh.ims.overlay 2>/dev/null
    sleep 1
    cmd overlay enable --user 0 com.dsh.ims.overlay 2>&1
  fi
  # phone process must re-read config_ims_package
  killall com.android.phone 2>/dev/null
  sleep 2
  killall com.android.phone 2>/dev/null
) &
