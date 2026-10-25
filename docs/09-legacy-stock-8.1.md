# 09 · 早期原厂 8.1 镜像工作

本仓库的主体是 **Android 9 GSI 的 Magisk 模块**。在转向 GSI 之前，还有一轮针对**原厂 Android 8.1 system 镜像**的工作：直接改镜像、fastboot 刷入，解决蓝牙、输入法、设置和 adb。两者不要混用。

## 为什么单列

- GSI 模块是 systemless、可开关、可回滚；
- 8.1 镜像是直接替换/注入 system 分区，刷错需要原镜像回滚；
- 8.1 镜像体积大（raw ext4 约 1.47 GB），**不纳入本仓库**，只保留方法和校验值。

## 蓝牙：不是禁用，是被物理删除

原厂 8.1 的 `system.img` 里：

| 组件 | 状态 |
|---|---|
| `/app/Bluetooth/Bluetooth.apk` | 不存在 |
| `libbluetooth_jni.so`、`lib/hw/bluetooth.default.so` | 不存在 |
| `/etc/bluetooth/bt_stack.conf`、`bt_did.conf` | 不存在 |
| `/etc/permissions/android.hardware.bluetooth{,_le}.xml` | 不存在（所以设置页连入口都不显示） |
| framework 的 `android.bluetooth.*` | 保留（333 处引用） |
| services 的 `BluetoothManagerService` | 保留（281 处引用） |
| SELinux 蓝牙规则、`user=bluetooth` 域 | 保留 |
| vendor 的蓝牙 HAL（`android.hardware.bluetooth@1.0-service-qti` 等） | 完整保留 |

所以 `settings put global bluetooth_on 1` 必然失败：没有任何进程能实现 `IBluetooth` 供 system_server 绑定。缺的是“本体”，不是开关。

修法：从 AOSP 8.1（phh GSI v23 = `android-8.1.0_r36`）取同代蓝牙文件注入原镜像，共 14 项新增、0 修改、0 删除。平台签名与原机 `framework-res.apk` 的证书逐字节相同（DER SHA-256 `c3e23a3b09e2937ced173a01bf8bea62`），共享 uid 成立。

## 设置：完整 AOSP，只是首页被改

软银的 `Settings.apk` 是完整 AOSP 8.1（versionCode 27，238 个 activity，117 个 dashboard 类），只是首页 fragment 在 dex 里被改成 `com.android.settings.admin.MainUnitSettingFragment`（5 个入口）。页面一个都没删，22 个原生设置页都能 `am start` 直达。

两种做法：

- **共存版**：新增 `com.android.settings.aosp`（`/priv-app/SettingsAosp/SettingsAosp.apk`，38.7 MB），保留原「設定」；
- **替换版**：整包替换 `/priv-app/Settings/Settings.apk`，保留包名 `com.android.settings`，并补一个 `activity-alias` 让桌面「設定」图标仍能打开。

替换版会失去软银专属页（省电、软件更新、相机限制、见守、礼仪模式等），共存版不会。

## 输入法

从 AOSP 8.1 注入 AOSP 键盘（含简中拼音）与 OpenWnn（日文），共 16 项。启用状态存在 `/data`，无法预置进只读 system，开机后需执行：

```sh
adb shell ime enable com.android.inputmethod.latin/.LatinIME
adb shell ime enable jp.co.omronsoft.openwnn/.OpenWnnJAJP
adb shell ime set com.android.inputmethod.latin/.LatinIME
```

## adb：整串精确匹配，顺序不能错

替换版把 `/build.prop` 两行改成：

```properties
persist.sys.usb.config=mtp,diag,adb
ro.sys.usb.default.config=mtp,diag,adb
```

不能写成 `diag,adb,mtp`。init 的属性触发器是整串精确匹配：

- `diag,adb,mtp` 在 vendor 的两套 rc 里都不存在 → 不配 gadget、不 `start adbd`，USB 什么都不通；
- `mtp,diag,adb` 存在（legacy 与 configfs 都有）→ `idVendor 05C6 / idProduct 903A`，`f_functions mtp,diag,adb`，`start adbd`。

限制：`persist.*` 只在键不存在时从 build.prop 取值。如果 `/data/property/persist.sys.usb.config` 已有旧值（例如之前刷过 LOS 的 `mtp,adb`），build.prop 会被忽略；旧值本身含 adb 时不影响使用。

## 镜像与校验值（不随仓库分发）

| 镜像 | 内容 | SHA-256 |
|---|---|---|
| 原始 | 回滚用 | `bed2a66f25ec66e818a3e5ccc34562f588afc8606c135cd935b592d6478ae36b` |
| 蓝牙 | 仅蓝牙 | `b012c60345a08df2dad1d8c419c6709855697eebd472bc93148e7691ba74008d`（sparse） |
| 蓝牙+输入法 | 无设置改动 | `c8c557e8993e2710da8274a6014ebb5ed46bb2736c5ddc920808b294994db2d6`（sparse） |
| 蓝牙+输入法+共存设置 | 推荐 | `c848673772a4b50b82d570cbd64883a53496c8f443f66571e91dc756a84ec385`（sparse） |
| 蓝牙+输入法+替换设置+adb | 单一设置入口 | `d0aead191117c9de4565946e3335805133d9bc0cb15667477e87ad69d02bcad4`（sparse） |

刷入方式：

```sh
fastboot flash system <image>.img
fastboot reboot
```

首次开机 PackageManager 要装新增系统应用并 dexopt，3–10 分钟属正常。官方 redbend FOTA 可能因 system 内容变化校验失败；依赖 OTA 就不要改 system。

## 与 GSI 模块的关系

- 这些镜像工作发生在**原厂 8.1**上，和本仓库的 GSI 模块无关；
- 刷了 GSI 之后不要再刷这些 8.1 system 镜像；
- 本仓库只保留方法、校验值和踩坑记录，不附带任何 system/boot 镜像。

## 工具链

当时为了不污染全局环境，全部工具放在工作目录内：

- 自编译 e2fsprogs 1.47.2（`debugfs -w` 注入、`e2fsck -fy` 校验）；
- 纯 Python 的 sparse/ext4 工具（sparse↔raw、ext4 全清单、二进制 Manifest、dex 工具、ELF 符号闭包）；
- apktool + aapt2 + `jarsigner`。

这些脚本没有全部纳入本仓库；需要时按文档中的命令复现。
