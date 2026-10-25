# 07 · 原厂相机依赖

对应修复：`modules/stockcam_helpers`（两个辅助 APK），相机 APK 本身不随仓库分发。

## 相机是什么

原厂 8.1 的相机是 `jp.co.seiko.kidsphone`（日文名「カメラ」），位于原厂 `/system/app/KidsCamera/KidsCamera.apk`：

- 59,790,607 字节；
- `minSdk/targetSdk 27`；
- 带 OpenCV + ImageMagick 特效引擎；
- 不是 AOSP 相机，GSI 里没有。

## 为什么直接装会崩

| # | 崩溃点 | 原因 | 解决 |
|---|---|---|---|
| 1 | `IllegalArgumentException: Unknown URL content://com.ssol.eventlog/eventlog`（`SystemEventLog.insertEvent`，`MainActivity.onCreate:126`） | 相机启动时要往原厂系统事件日志写一条记录。原厂 provider 是 `/priv-app/EventLog`（`com.ssol.eventlog`，`sharedUserId=android.uid.system`，OEM 平台签名），GSI 上装不进去 | 补一个同 authority 的替身 provider `com.dsh.eventlogstub`（普通应用，仅接受写入并返回一个 Uri） |
| 2 | `ActivityNotFoundException: {org.codeaurora.gallery/com.android.gallery3d.app.GalleryActivity}`（`MainActivity.launchAlbumAppBody:901`） | 点缩略图/相册按钮时硬编码启动原厂相册 `org.codeaurora.gallery`。原厂 SnapdragonGallery 装不上：`INSTALL_FAILED_DUPLICATE_PERMISSION: com.android.gallery3d.permission.GALLERY_PROVIDER already owned by com.android.gallery3d`（GSI 自带 Gallery2） | 装一个只占包名和 Activity 名的转接包 `org.codeaurora.gallery`，收到 intent 后转给系统的 `com.android.gallery3d/.app.GalleryActivity` |

相机 APK 的签名是 **phh GSI 的同一把平台证书**（SHA-256 `c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8`），所以装成普通应用后它仍落在 `platform_app` 域、能用反射写系统属性——它用这个控制快门音。非 phh 系 GSI 平台证书不同，行为可能变化。

## 从自己的原厂镜像提取

```sh
debugfs -R "dump /app/KidsCamera/KidsCamera.apk ./KidsCamera.apk" /path/to/stock-system.img
```

`debugfs` 来自 e2fsprogs。可以先 `debugfs -R "ls -l /app"` 确认路径。

仓库里的 `tools/extract-kids-camera.sh` 是一个带参数检查的封装：

```sh
tools/extract-kids-camera.sh /path/to/stock-system.img ./KidsCamera.apk
```

## 安装

```sh
adb install -r KidsCamera.apk
adb push stockcam_helpers-v1.0.zip /data/local/tmp/
adb shell su -c 'magisk --install-module /data/local/tmp/stockcam_helpers-v1.0.zip'
# 重启一次：模块开机后自动安装两个补丁包并授予相机运行权限
```

不用 Magisk 模块时，手工两步（补丁包在 zip 的 `apks/` 里）：

```sh
adb install -r apks/eventlogstub.apk       # 包名 com.dsh.eventlogstub，占用 authority com.ssol.eventlog
adb install -r apks/gallerybridge.apk      # 包名 org.codeaurora.gallery，转发到系统 Gallery2
adb shell pm grant jp.co.seiko.kidsphone android.permission.CAMERA
adb shell pm grant jp.co.seiko.kidsphone android.permission.RECORD_AUDIO
adb shell pm grant jp.co.seiko.kidsphone android.permission.READ_EXTERNAL_STORAGE
adb shell pm grant jp.co.seiko.kidsphone android.permission.WRITE_EXTERNAL_STORAGE
```

权限不授予时，日志里是 `CameraService: Permission Denial: can't use the camera`，界面卡在灰底相机图标。

## 两个辅助 APK 的实现

源码在 `apk-src/`：

- `eventlogstub`：`com.dsh.eventlogstub.EventLogProvider`，authority `com.ssol.eventlog`，`query` 返回空 `MatrixCursor`，`insert` 返回 `content://com.ssol.eventlog/eventlog/1`，`delete/update` 返回 0；
- `gallerybridge`：包名 `org.codeaurora.gallery`，Activity 名 `com.android.gallery3d.app.GalleryActivity`，`onCreate` 把 intent 的 component 改成 `com.android.gallery3d/.app.GalleryActivity` 再 `startActivityForResult`，结果原样回传。

## 验证

```sh
adb shell 'logcat -d | grep -E "kidsphone|EventLogProvider|GalleryBridge"'
```

- 能进预览、有对焦框、按快门后 `/sdcard/DCIM/Camera/IMG_*.jpg` 增加；
- 点缩略图 → `GalleryBridge: forwarding to Gallery2`，随后 `com.android.gallery3d/.app.GalleryActivity` 起来；
- 正常拍照还依赖 [03-camera-jpeg.md](03-camera-jpeg.md) 的 JPEG HAL 补丁；没有它按快门会卡住且不存盘。

## 快门音

这个 APK 里没有任何音频资源（0 个 ogg/mp3/wav），`SoundEffectManager.playShutter()` 是空函数。它控制声音只有两个方式：

1. `jp.co.seiko.kidscamera.util.SystemCameraSound`：`onResume()` 反射 `android.os.SystemProperties.set("persist.camera.sound.control","0")`，`onPause()` 设为 `"1"`；
2. 两处 `android.hardware.Camera.enableShutterSound(true)`。

真正发声的是框架相机服务（`/system/lib/libcameraservice.so` 里的 `camera_click`，音效文件 `/system/media/audio/ui/camera_click.ogg`）。日本本土机型靠 `ro.camera.sound.forced` 强制出声。phh v23 上该属性为空，`persist.camera.sound.control` 也不被 vendor 相机 HAL 读取（`/vendor/lib/hw/camera.msm8909.so` 里该字符串出现 0 次），**实测拍照完全无声**。想要声音只能另外加，但那就不是原厂行为了。

## 限制

- 相机功能完整（预览/拍照/录像/翻转/闪光灯/特效编辑），但没有陀螺仪硬件，所以没有依赖陀螺的功能。
- 相册按钮打开的是 GSI 自带的 Gallery2，不是原厂 SnapdragonGallery（后者与系统 Gallery2 权限冲突，装不上）。
- 两个补丁包是普通应用，恢复出厂/重刷 system 会丢；Magisk 模块会在每次开机补齐。
- 相机 APK 属于原厂私有软件，本仓库不附带，请从自己的设备镜像提取。
- 重新签名辅助 APK 后覆盖安装会因签名不一致失败；先卸载旧包，或保留模块内置的 CN=dsh 签名版本。
