# 901si GSI 修复模块

给 **SoftBank 901si**（KYV41 同平台，高通 msm8909 + Adreno 304）刷 **Android 9 GSI** 之后用的一套 Magisk 修复模块。共 5 个模块，彼此独立，可以只装需要的；全部通过 Magisk 挂载/运行时属性实现，**不刷 boot、不改分区**，禁用模块并重启即可回滚。

> English: [README.en.md](README.en.md)

## AI 辅助声明

本仓库的代码、脚本、文档与排查记录在编写过程中使用了 **AI 辅助**（DeepSeek Harness 中的编码智能体）。所有修改均在真实设备（901si，Android 9 GSI）上实际安装、运行和验证，结论以设备日志与实测结果为准。

但 AI 生成的内容仍可能包含错误、过时信息，或对你所用设备/系统版本不成立的假设。**刷入任何模块前，请自行阅读源码、核对校验值并备份原厂镜像。** 因使用本仓库内容造成的设备损坏、数据丢失或功能异常，由使用者自行承担。

## 为什么会有这个仓库

这台机器原厂是 Android 8.1，vendor 分区停留在 2020-04-09 的版本。换上 Android 9 GSI（phh v23 / LineageOS 16）后，系统能启动，但有几处“8.1 的 vendor 与 9 的 framework 对不上”的硬伤：

- 界面闪屏、黑块、上一屏残影；
- 视频只有声音没有画面；
- 拍照后相机定格、照片不落盘；
- 自动旋转永远不工作；
- 红/绿状态灯不亮，或开机一直亮绿灯；
- VoLTE 不可用；
- 原厂相机「カメラ」启动即崩。

这些都不是“再刷一个包”能解决的，而是需要逐项定位到寄存器/属性/二进制补丁。这里把最终能用的方案、源码、构建脚本和踩过的坑一起留下。

## 适用条件

| 项 | 值 |
|---|---|
| 设备 | SoftBank 901si（KYV41 同平台），msm8909，Adreno 304 |
| 系统 | Android 9 GSI，A-only，32 位（测试：phh v23 / LineageOS 16.0） |
| 原厂底包 | Android 8.1.0，vendor 2020-04-09，内核 3.18.71 |
| 前提 | 已 root（Magisk）；能使用 `resetprop`、`magiskpolicy` |
| 不适用 | 64 位 GSI、A/B 分区机型、非 msm8909 / 非 SLG4AX 灯控 / 非 LIS2DS12 加速度计 |

模块只针对上述基线验证过。相同 SoC 的其它机型可以借鉴思路，但路径、寄存器、HAL 名称可能不同，不要直接照搬。

## 模块一览

| 模块 | 版本 | 解决的问题 | 发布件 |
|---|---|---|---|
| `901si_gsi_fixes` | v1.0 | HWUI 闪屏/残影、venus 硬解、JPEG HAL 拍照 abort | `901si-gsi-fixes-v1.0.zip` |
| `lis2ds12_int` | v1.3 | LIS2DS12 数据就绪中断未路由，自动旋转失效 | `lis2ds12_int-v1.3.zip` |
| `ledlineage` | v1.2 | 厂商灯 HAL 路径不存在 + SELinux 拒绝；v1.2 降低轮询开销并压掉开机绿灯 | `ledlineage-v1.2.zip` |
| `volte_caf` | v0.1 | GSI 缺 CAF IMS 栈，VoLTE 无法注册 | `volte_caf-v0.1.zip` |
| `stockcam_helpers` | v1.0 | 原厂相机缺少事件日志 provider 与相册组件 | `stockcam_helpers-v1.0.zip` |

发布页的 `SHA256SUMS` 是最终校验值；源码里的版本号与 zip 内 `module.prop` 一致。

## 快速开始

1. 从 [Releases](https://github.com/PDWYX/901si-gsi-fixes/releases) 下载需要的 zip；
2. 传到手机；
3. Magisk App →「模块」→「从本地安装」→ 选择 zip；
4. 重启。

也可以命令行安装（注意：这台机器的 `adb shell su -c` 会话看不到 `/data/adb`，要用 `magisk --install-module`）：

```sh
adb push 901si-gsi-fixes-v1.0.zip /data/local/tmp/
adb shell su -c 'magisk --install-module /data/local/tmp/901si-gsi-fixes-v1.0.zip'
adb reboot
```

推荐顺序：先装 `901si_gsi_fixes`，确认显示/视频/相机正常；再按需装其它模块。互不依赖。

## 各项修复

### 1. 闪屏、黑块、残影（`901si_gsi_fixes`）

**现象**：下拉通知栏、展开设置里的折叠项、滑动列表时，屏幕顶部出现黑块和上一屏的残影；手指一停就不闪。

**根因**：Adreno 304 驱动声明了 `EGL_KHR_partial_update`，但 `eglQuerySurface(EGL_BUFFER_AGE_EXT)` 返回的缓冲年龄是错的（实测恒为 2）。Android 9 的 HWUI 相信这个值，走 `SwapBehavior::BufferAge` 复用旧帧；再叠加 SurfaceFlinger 的双缓冲（`DISABLE_TRIPLE_BUFFERING`），残影立刻显形。

**修法**：`post-fs-data.sh` 里设置

```
debug.hwui.use_buffer_age=false
```

HWUI 回落到整帧保留（`SwapBehavior::Preserved`）。代价是每帧多画一点，480×800 下无感。

### 2. 视频只有声音没有画面（`901si_gsi_fixes`）

**现象**：任何播放器播 H.264/HEVC 都只有声音，画面全黑。

**根因**：Android 9 的 ACodec 建解码会话时请求 **DPB/OPB 分离模式**：

```
D OMX-VDEC-1080P: DPB mode: split DPB color format: nv12_ubwc OPB color format: nv12
E OMX-VDEC-1080P: Failed to set ext ctrls for opb_dpb: -1
err: HFI_EVENT_SESSION_ERROR / warn: Unsupported bitstream in 00000000
```

本机 venus 固件是 8.1 时代的，不认识这个模式，直接销毁会话。后面那句 `Unsupported bitstream` 是**会话已经被拆掉之后**打出来的，不是真的读不懂码流，很容易把排查方向带偏。

**修法**：设置

```
vendor.vidc.disable.split.mode=1
```

让组件退回 8.1 的合并模式（DPB 与 OPB 共用缓冲）。这是高通源码 `omx_vdec_v4l2.cpp` 里自带的开关。实测 `OMX.qcom.video.decoder.avc/hevc` 恢复，1080p30 HEVC 流畅。

### 3. 拍照后定格、照片不保存（`901si_gsi_fixes`）

**现象**：预览、录像正常；按快门后画面定格，`/sdcard/DCIM/Camera` 没有新照片。

**根因**：拍照其实已经成功（JPEG 编码完成），但 HAL 释放会话时 `QImageHybridEncoder::ReleaseSession()` 第二次销毁同一个互斥锁。Android 8.1 的 bionic 只返回错误码，Android 9 的 FORTIFY 直接 abort：

```
F/libc: FORTIFY: pthread_mutex_destroy called on a destroyed mutex
F/libc: Fatal signal 6 (SIGABRT) in tid 839 (OMX_ImgEnc)
```

相机 provider 进程当场死亡，于是预览定格、照片没写盘。

**修法**：把 `ReleaseSession` 里两条 `bl os_mutex_destroy` / `bl os_cond_destroy` 改成 Thumb NOP（`00 BF 00 BF`）。167620 字节的库只改 8 字节，见 [`patches/jpeg/`](patches/jpeg/)。

模块的 `customize.sh` 会校验 `/vendor/lib/libmmqjpeg_codec.so` 的 md5：

| 版本 | md5 |
|---|---|
| 原厂 | `73d3594e71ed0866194ecaab845b781b` |
| 补丁版 | `d6911e58ee5a2b2146022041152066b6` |

不匹配时**自动跳过相机补丁**，只装两个属性修复，不会把相机 HAL 弄坏。

### 4. 自动旋转完全不可用（`lis2ds12_int`）

**现象**：自动旋转开关能开，屏幕永不旋转；`dumpsys sensorservice` 里 `lis2ds12-accel` 显示 `status: active`，但没有采样。

**根因**：LIS2DS12 的数据就绪中断路由寄存器 **CTRL4（0x23）从来没被写过**，INT1（GPIO58）不触发，内核驱动收不到样本。芯片本身在正常采样（直接读 0x28–0x2D 能看到数据在变）。原厂 8.1 用同一份 vendor HAL、同一个内核和设备树，所以**原厂也没有自动旋转**，不是 GSI 弄坏的。

**修法**：独立模块的 `service.sh` 每秒检查一次，`enable=1` 且 `0x23 != 0x01` 时补写 `0x23=0x01`（脉冲型，每样本一个中断，50 Hz）。

**关键**：必须写 `0x23`，不能写 `0x22`。`0x22` bit0 是锁存型输出，会产生约 **390 次/秒**的伪中断（实测吃掉约 1.5 个 CPU 核，界面卡顿、列表回弹）；`0x23` bit0 是脉冲型，正好 50 次/秒。详细寄存器实验见 [`docs/04-accelerometer.md`](docs/04-accelerometer.md)。

关闭开关：`touch /data/local/tmp/lis2ds12_off` 后重启。

### 5. 红/绿状态灯不亮（`ledlineage`）

**现象**：刷 GSI 后状态灯完全不亮；开机还会一直亮绿灯。

**根因**：两件事同时挡着：

1. 厂商灯 HAL `lights.msm8909.so` 硬编码 `/sys/class/leds/{red,green,blue}/brightness`，本机驱动只有 `/sys/class/leds/slg4ax42959v_led/{redled,greenled,blueled,poweron}`；
2. `hal_light_default` 域对 sysfs 没有写权限，`logcat` 里是 `rc=-13`。

**修法**：`post-fs-data.sh` 用 tmpfs 覆盖 `/sys/class/leds`，把原有条目（背光、手电筒等）bind mount 回去，新建 `red/green/blue` 兼容节点并 `chmod 666`，再用 `magiskpolicy --live` 给 `hal_light_default` 放行。`daemon.sh` 把 HAL 下发的 0–255 亮度翻译成驱动认的 pattern `0/1`，并保持 `poweron=1`。

**安全阀**：如果覆盖后读不到 `lcd-backlight/brightness`，立刻 `umount` 回滚，不会留下黑屏。

**v1.2（当前版本）**：v1.0 的守护每 0.15 秒用 `cat`/`tr` 读节点，每秒产生约 40 个短命进程，长期占用约 2% 单核；v1.1 改成纯 shell 内建、零 fork，并把轮询放宽到 0.4 秒。v1.2 在此基础上把轮询收紧到 0.25 秒，开机前 50 秒无条件回写 pattern，并在 `post-fs-data` 阶段先清零三路再开 `poweron`，把驱动 probe 默认点亮的绿灯压掉。实测平均响应约 0.23 秒、CPU 约 0.5% 单核（v1.0 约 2.0%）。

> **旧版已撤下**：`ledlineage-v1.0.zip` 已从 Releases 移除，请使用 v1.2。旧版并不会损坏设备，只是守护进程更耗电、开机绿灯窗口更长。

### 6. VoLTE（`volte_caf`）

**背景**：vendor 侧 IMS HIDL 服务齐全（`imsradio0`、`imscmservice` 都在线），system 侧却缺 `org.codeaurora.ims`；`framework-res` 里 `config_ims_package=""`、`config_dynamic_bind_ims=false`，`ImsResolver` 谁都不找。所以只改 build.prop 开关没有用。

**修法**：

1. 把 phh GSI 重编的 `ims.apk`（`org.codeaurora.ims`，testkey 签名，`sharedUserId=android.uid.phone`）放进 `/system/priv-app/ims/`；
2. 把 APK 里的 **38 个 .so 全部解到 `/system/priv-app/ims/lib/arm/`**；
3. 用预装 RRO `com.dsh.ims.overlay` 覆盖 `config_ims_package` / `config_dynamic_bind_ims`，RRO 必须放在 `/system/app/`；
4. 设置 `persist.dbg.ims_volte_enable` 等属性；开机后启用 overlay 并重启 `com.android.phone`。

实测中国移动：`REQUEST_IMS_REGISTRATION_STATE ... state: 2 radioTech: 14`，通话走 IMS 且保持 LTE。

### 7. 原厂相机（`stockcam_helpers`）

原厂相机是 `jp.co.seiko.kidsphone`（日文名「カメラ」），不是 AOSP 相机，GSI 里没有，需要从自己的原厂镜像提取。它直接装到 GSI 会因两个依赖缺失而崩：

| 崩溃点 | 原因 | 解决 |
|---|---|---|
| `Unknown URL content://com.ssol.eventlog/eventlog` | 原厂 `EventLog` provider 是 OEM 平台签名，GSI 没有 | 安装同 authority 的替身 `com.dsh.eventlogstub` |
| `ActivityNotFoundException: {org.codeaurora.gallery/...}` | 原厂 SnapdragonGallery 与 GSI 自带 Gallery2 权限冲突，装不上 | 安装只占包名/Activity 名的转接包 `org.codeaurora.gallery`，转发到 `com.android.gallery3d/.app.GalleryActivity` |

模块开机自动安装两个补丁 APK，并补齐相机的 CAMERA / RECORD_AUDIO / READ / WRITE_EXTERNAL_STORAGE 权限。**相机 APK 本身不随仓库分发**，见 [`docs/07-stock-camera.md`](docs/07-stock-camera.md)。

## 已知的坑（重要）

这一节比上面的“修了什么”更重要。下面每一条都是实际踩过、会浪费一整晚的坑。

| # | 坑 | 后果 | 正确做法 |
|---|---|---|---|
| 1 | 加速度计写 `0x22=0x01` | 约 390 次/秒伪中断，界面卡顿、列表回弹 | 只写 `0x23=0x01`（脉冲型） |
| 2 | 写 `slg4ax42959v_led/trigger` 或全局 `brightness` | **内核崩溃、设备重启**（实测两次） | 只写 `redled/greenled/blueled` 的 pattern `0/1`，保持 `poweron=1` |
| 3 | 把 VoLTE 的 38 个 .so 留在 APK 里 | `UnsatisfiedLinkError: libimsmedia_jni.so`，`com.android.phone` 无限崩溃 | 必须解到 `system/priv-app/ims/lib/arm/` |
| 4 | 用 `pm install` 装 IMS RRO | `must be signed with the platform certificate` | RRO 预装到 `/system/app/`（预装路径不校验签名） |
| 5 | 以为 `Unsupported bitstream` 是码流问题 | 一直去改解码器/换播放器，方向全错 | 先看前面有没有 `DPB mode: split` 和 `HFI_EVENT_SESSION_ERROR`；这是会话被拆后的尸体日志 |
| 6 | 以为自动旋转要改 DT / 刷 boot | 白刷 boot，问题依旧 | 只写 CTRL4 `0x23=0x01` 即可；DT `st,enable-int` 非必需 |
| 7 | 换了社区 Adreno 3xx 驱动 | 驱动更旧（V@145 vs 本机 V@269），固件逐字节相同，只会降级 | 不要换；HWC 全 Client 是 SDM 单 GPU_TARGET 的既定策略，不是故障 |
| 8 | 用早期 `libOmxVdec.so` 二进制补丁 | 最终证明不需要；属性方案已足够 | 用 `vendor.vidc.disable.split.mode=1`，不要再叠二进制补丁 |
| 9 | 同时装 `vdec_hwfix` 和 `901si_gsi_fixes` | 两个模块抢同一组属性，行为不可预期 | 只保留一个；本仓库的模块已包含该属性 |
| 10 | 装过“强制软解”的 `media_codecs.xml` 覆盖 | 硬解不会生效，看起来像模块没用 | 先移除软解模块，再验证硬解 |
| 11 | 在别的 GSI/机型上照搬 `debug.hwui.use_buffer_age=false` | 正常支持 buffer age 的 GPU 会失去局部更新优化，增加功耗 | 只在这颗 Adreno 304 + 这套驱动上用 |
| 12 | 在支持 DPB/OPB split 的新固件上强制 `disable.split.mode=1` | 能用，但退回合并模式，性能和内存利用略降 | 新固件不要加这条；本机是 8.1 venus 才需要 |
| 13 | 原厂相机 APK 换到非 phh GSI | 平台签名不同，依赖系统权限/属性的功能可能异常 | 用 phh 系 GSI，或自行重签/改权限；本仓库不带相机 APK |
| 14 | 在还有原厂 `EventLog` 的 8.1 系统上装 `eventlogstub` | authority 冲突，provider 安装失败 | 只在 GSI 上用；原厂系统不需要 |
| 15 | 在还有原厂 SnapdragonGallery 的系统上装 `gallerybridge` | 包名冲突 | 只在 GSI（自带 Gallery2）上用 |
| 16 | 以为本机有陀螺仪 | 指南针/VR/防抖永远不可用，误判为“没修好” | 本机只有距离、光线、加速度三颗传感器，硬件不存在 |
| 17 | `adb shell su -c` 里操作 `/data/adb` | 这个 root 会话看不到该目录，脚本“找不到模块” | 用 `adb shell su -c 'magisk --install-module ...'`，或直接在 Magisk App 里装 |
| 18 | 装完不重启 | `resetprop` 在 post-fs-data 执行，overlay 也要开机后才启用 | 必须重启；VoLTE 首次启动还会重启一次 `com.android.phone` |
| 19 | 把 32 位 VoLTE 包用在 64 位 GSI | IMS 起不来或崩溃 | 64 位设备换 [khrj/volte-fix](https://github.com/khrj/volte-fix) 的 `64bit/ims` |
| 20 | 重新签名 `stockcam_helpers` 的 APK 后覆盖安装 | 与已安装旧包签名不一致，`pm install -r` 失败 | 要么卸载旧包再装，要么保留模块里预置的 CN=dsh 签名版本 |
| 21 | 在 A/B 或 64 位机型上刷这些模块 | 路径/库/属性都不对应，可能无法开机 | 仅用于 A-only 32 位 msm8909 901si |
| 22 | 把模块里的厂商二进制当开源代码再分发 | 版权/许可问题 | 仅个人修复使用；见 [NOTICE.md](NOTICE.md) |

### 关于“写 LED 节点会重启”的细节

在这台机器上，`slg4ax42959v_led/trigger` 和 `slg4ax42959v_led/brightness` 不是普通可写节点；写入会触发内核崩溃。模块只碰：

- `slg4ax42959v_led/poweron`
- `slg4ax42959v_led/redled`
- `slg4ax42959v_led/greenled`
- `slg4ax42959v_led/blueled`

如果你要自己改脚本，**不要**“顺手”加 `trigger` 或全局亮度。

### 关于“为什么不用现成方案”

- 社区 Adreno 3xx 驱动（multiwirth / osm0sis）都是 V@145.0（2016），本机是 V@269（2018-12）；`a330_pfp.fw` / `a330_pm4.fw` 与本机逐字节相同。换驱动只会降级，路线关闭。
- 早期试过给 `libOmxVdec.so` 打二进制补丁、改 DT `st,enable-int`、强制软解 `media_codecs.xml`；最终都证明不是必需或不是最优。保留记录见 [`docs/08-dead-ends.md`](docs/08-dead-ends.md)。

## 验证

```sh
# 属性
adb shell su -c 'getprop debug.hwui.use_buffer_age'          # false
adb shell su -c 'getprop vendor.vidc.disable.split.mode'    # 1
adb shell su -c 'getprop persist.dbg.ims_volte_enable'      # 1

# 加速度计：5 秒计数差约 250（50 Hz）
adb shell su -c 'grep lis2ds12 /proc/interrupts; sleep 5; grep lis2ds12 /proc/interrupts'

# 寄存器
adb shell su -c 'echo 0x23 > /sys/bus/i2c/devices/1-001d/reg_addr; cat /sys/bus/i2c/devices/1-001d/reg_value'
# 0x01

# 状态灯节点
adb shell su -c 'ls /sys/class/leds/red /sys/class/leds/green'

# IMS 注册（state: 2 = 已注册）
adb shell su -c 'dumpsys telephony.registry | grep -i ims'
```

也可以直接跑 `tools/verify.sh`（需要 adb + root）。

## 从源码构建

```sh
# 重新打 5 个 Magisk 模块 -> dist/
tools/build-release.sh

# 重新编译两个相机辅助 APK（需要 Android SDK）
ANDROID_HOME=/path/to/android-sdk tools/build-apks.sh

# 重新编译 VoLTE RRO
ANDROID_HOME=/path/to/android-sdk tools/build-overlay.sh
```

发布件不提交到 git，由 GitHub Releases 托管；`dist/` 和 `build/` 已在 `.gitignore` 里。

## 目录结构

```
.
├── modules/                 # 5 个模块的源码（zip 内容）
│   ├── 901si_gsi_fixes/
│   ├── lis2ds12_int/
│   ├── ledlineage/
│   ├── stockcam_helpers/
│   └── volte_caf/
├── patches/jpeg/            # JPEG HAL 的 8 字节补丁 + 说明
├── apk-src/                 # 两个相机辅助 APK 的 Java 源码
├── overlay-src/ims/         # VoLTE RRO 源码
├── tools/                   # 打包、编译、提取、验证脚本
├── docs/                    # 逐项根因与实验记录
├── README.md                # 中文
├── README.en.md             # English
├── NOTICE.md                # 第三方组件与许可
└── LICENSE                  # MIT（仅仓库内脚本/源码）
```

## 回滚

- 通用：Magisk App 里关闭对应模块 → 重启；
- 或 `touch /data/adb/modules/<id>/disable` → 重启；
- 或 `rm -rf /data/adb/modules/<id>` → 重启。

模块本身不改分区：属性是运行时 `resetprop`，文件是 Magisk magic mount，`ledlineage` 的 tmpfs/bind mount 也在重启后消失。唯一留在 `/data` 的是 `stockcam_helpers` 安装的两个普通 APK；不需要时手动 `pm uninstall com.dsh.eventlogstub org.codeaurora.gallery`。

## 研究记录

- [01 · HWUI 缓冲代龄与闪屏](docs/01-buffer-age.md)
- [02 · venus DPB/OPB split 与硬解](docs/02-video-decode.md)
- [03 · JPEG HAL 二次销毁互斥锁](docs/03-camera-jpeg.md)
- [04 · LIS2DS12 中断路由实验](docs/04-accelerometer.md)
- [05 · SLG4AX 状态灯与 SELinux](docs/05-led.md)
- [06 · CAF IMS 与 VoLTE](docs/06-volte.md)
- [07 · 原厂相机依赖](docs/07-stock-camera.md)
- [08 · 死路与未采纳方案](docs/08-dead-ends.md)
- [09 · 早期原厂 8.1 镜像工作](docs/09-legacy-stock-8.1.md)

## 致谢

- [phhusson/treble_experimentations](https://github.com/phhusson/treble_experimentations)：GSI 与平台签名基线；
- [khrj/volte-fix](https://github.com/khrj/volte-fix)：为 phh GSI 重编的 CAF IMS 栈；
- AOSP / LineageOS：HWUI、ACodec、Gallery2；
- Magisk / topjohnwu：模块与 `resetprop` / `magiskpolicy`。

## 许可

仓库内脚本与自行编写的 Java 源码采用 MIT，见 [LICENSE](LICENSE)。
模块中包含的厂商二进制（`libmmqjpeg_codec.so`、`ims.apk` 及其 `.so`、RRO 等）版权归各自权利人所有，**不适用 MIT**，仅用于个人设备修复；详见 [NOTICE.md](NOTICE.md)。

---

**免责声明**：这些修改直接作用于相机 HAL、视频解码器、IMS 和状态灯驱动，存在设备不稳定/无法开机的风险。请先确认你有原厂镜像和救砖手段。按 MIT 许可“按原样”提供，不提供任何担保。
