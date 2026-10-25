# 03 · JPEG HAL 二次销毁互斥锁

对应修复：`modules/901si_gsi_fixes`（替换 `/vendor/lib/libmmqjpeg_codec.so`）与 `patches/jpeg/`。

## 现象

预览正常、录像正常；按快门后画面定格，`/sdcard/DCIM/Camera` 没有新照片。相机 App 不一定立刻退出，但 provider 进程已经死了。

## 日志

```
F/libc: FORTIFY: pthread_mutex_destroy called on a destroyed mutex
F/libc: Fatal signal 6 (SIGABRT) in tid 839 (OMX_ImgEnc)
```

## 根因

拍照其实已经成功：JPEG 编码完成，文件数据已经产生。问题出在释放编码会话时，`QImageHybridEncoder::ReleaseSession()` 对同一个互斥锁/条件变量调用了第二次 destroy。

- Android 8.1 的 bionic：检测到已销毁，返回错误码，进程继续；
- Android 9 的 bionic：FORTIFY 直接 `abort()`。

相机 provider 进程收到 SIGABRT，于是预览定格、照片没有写盘。

## 补丁

把 `ReleaseSession()` 里两条 Thumb BL 指令改成 NOP：

| 文件偏移 | 原字节 | 补丁后 | 作用 |
|---|---|---|---|
| `0x20742` | `e8 f7 1a ec` | `00 bf 00 bf` | 跳过 `os_mutex_destroy` |
| `0x20752` | `e8 f7 18 ec` | `00 bf 00 bf` | 跳过 `os_cond_destroy` |

167,620 字节的文件只改 8 字节。Thumb 的 `00 BF` 是 `nop`，两条 4 字节 BL 各覆盖为两个 NOP。

| 版本 | md5 |
|---|---|
| 原厂 | `73d3594e71ed0866194ecaab845b781b` |
| 补丁版 | `d6911e58ee5a2b2146022041152066b6` |

## 复现补丁

```sh
python3 patches/jpeg/patch_mmqjpeg.py \
    /path/to/stock/libmmqjpeg_codec.so \
    ./libmmqjpeg_codec.so
```

脚本会：

1. 校验输入 md5 必须是原厂或已补丁版；
2. 确认两条特征字节在文件中各只出现一次；
3. 替换并校验输出 md5。

不是这个版本就拒绝，避免误伤别的相机 HAL。

## 模块侧的保护

`modules/901si_gsi_fixes/customize.sh` 在安装时再次校验：

```sh
EXPECT=73d3594e71ed0866194ecaab845b781b
PATCHED=d6911e58ee5a2b2146022041152066b6
CUR=$(md5sum /vendor/lib/libmmqjpeg_codec.so | awk '{print $1}')
```

不匹配时删除 `$MODPATH/system`，**只安装两个属性修复**，不会把相机 HAL 换坏。

## 验证

```sh
adb shell su -c 'md5sum /vendor/lib/libmmqjpeg_codec.so'
# d6911e58ee5a2b2146022041152066b6

adb shell 'logcat -c; am start -a android.media.action.IMAGE_CAPTURE'
# 拍照后
adb shell 'logcat -d | grep -E "FORTIFY|SIGABRT|OMX_ImgEnc"'
# 应无输出
adb shell 'ls -l /sdcard/DCIM/Camera | tail'
```

## 边界

- 只适用于上述 md5 的 32 位库。64 位 GSI 的 `lib64` 版本偏移不同，不要直接用。
- 这个补丁让 destroy 变成 no-op，理论上会泄漏一次锁资源；但会话本来就只创建/销毁一次，实测长期拍照无异常。
- 相机 APK 本身不随仓库分发，见 [07-stock-camera.md](07-stock-camera.md)。
