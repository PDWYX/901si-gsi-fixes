# 06 · CAF IMS 与 VoLTE

对应修复：`modules/volte_caf`。

## 背景：该有的都有，只缺一个应用

刷 Android 9 GSI 之后：

- **vendor 侧齐全**：`lib-imscmservice.so`、`imsdatadaemon`、`ims_rtp_daemon`、`imsqmidaemon` 都在跑；`lshal` 能看到 `vendor.qti.hardware.radio.ims@1.0::IImsRadio/imsradio0`、`com.qualcomm.qti.imscmservice@1.0` 在线；
- **system 侧缺失**：`org.codeaurora.ims`（高通 IMS 应用）不存在；`framework-res` 里 `config_ims_package=""`、`config_dynamic_bind_ims=false`，于是 `ImsResolver` 谁都不找。

所以“改 build.prop 开关”没有用：没有 IMS 应用，就没有东西去驱动 vendor 的 IMS HAL。

## 修法（三件事）

### 1. 装 IMS 应用

把社区为 phh GSI 重编的 `ims.apk`（`org.codeaurora.ims`，targetSdk 27，AOSP testkey 签名，与 GSI 同签名，所以 `sharedUserId=android.uid.phone` 能通过）放进 `/system/priv-app/ims/`。

**必须把 APK 里的 38 个 `.so` 全部解到 `/system/priv-app/ims/lib/arm/`。** 系统应用正常由 installd 在安装时解压 `.so`，但 Magisk 挂载的 APK 没法往只读的 `/system` 里解压；结果是：

```
UnsatisfiedLinkError: couldn't find "libimsmedia_jni.so"
```

然后 `com.android.phone` 无限崩溃重启。

> 为什么是 38：这是该 APK 的 `lib/arm/` 实际条目数。构建时直接 `unzip -l` 数，不要猜。

### 2. 让框架认识它

加一个 RRO 覆盖层 `com.dsh.ims.overlay`，覆盖两个框架资源：

```xml
<string name="config_ims_package">org.codeaurora.ims</string>
<bool name="config_dynamic_bind_ims">true</bool>
```

**关键细节：覆盖层必须作为预装系统应用放在 `/system/app/`（或 `priv-app`）。** 用 `pm install` 装到 data 分区会被拒绝：

```
INSTALL_FAILED_INTERNAL_ERROR: Overlay ... must be signed with the platform certificate.
```

预装路径不校验签名，所以用自己的密钥签名也能用（phh v23 实测通过）。

### 3. 开属性并重启电话服务

```
persist.dbg.ims_volte_enable=1
persist.dbg.volte_avail_ovr=1
persist.dbg.vt_avail_ovr=1
persist.dbg.wfc_avail_ovr=1
persist.dbg.allow_ims_off=1
```

`service.sh` 开机后 `cmd overlay enable`，再重启一次 `com.android.phone`，让它重读配置。首次启动会重启一次，属正常。

## 验证（中国移动，phh v23，901si）

```
ImsResolver: ImsServiceController added on slot: 0 with feature: 1   <- MMTEL
MmTelFeatureConnection: MmTel enabled on slotId: 0
QImsService: REQUEST_IMS_REGISTRATION_STATE ... state: 2 radioTech: 14
MmTelFeatureConnection: onRegistering :: -> onRegistered ::
QImsService: ImsServiceSub: [0] VOLTE ims registered
ImsCall: callSessionUpdated :: state:ESTABLISHED ... tech:14
```

- `state: 2` = 已注册；
- `radioTech: 14` = LTE；
- 设置里出现“增强型 4G LTE”开关；
- 接打电话正常，通话期间保持 LTE（无 CS 回落）；
- 重启后自动生效。

## 适用性

- 只对**高通平台、vendor 侧有 IMS HIDL 服务**的机器有意义（`lshal | grep ims` 能看到 `imsradio0`）。
- 用的是 phh GSI 的 32 位包；64 位设备需换 [khrj/volte-fix](https://github.com/khrj/volte-fix) 的 `64bit/ims`。
- `mVoLteServiceState` 在某些运营商配置下仍显示未设置（`2147483647`），只是状态栏文案的账，不影响通话。
- 中国移动的 carrier config 里 `carrier_volte_available_bool=false`，但实测 IMS 注册与通话均正常，不需要改运营商配置。

## 回滚

`touch /data/adb/modules/volte_caf/disable` 或删除模块目录，重启。全部是 Magisk 挂载，不动分区。

## 坑

1. 38 个 `.so` 留在 APK 里 → `UnsatisfiedLinkError` → 电话崩溃循环。
2. RRO 用 `pm install` → 平台证书错误。
3. 只改属性、不装 IMS 应用 → `ImsResolver` 仍然绑不到任何东西。
4. 用 32 位包上 64 位 GSI → IMS 起不来或崩溃。
