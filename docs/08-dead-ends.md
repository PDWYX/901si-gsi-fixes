# 08 · 死路与未采纳方案

记录那些“看起来能修、实际不行或不再需要”的路线，避免后来者重复烧时间。

## 1. 换社区 Adreno 3xx 驱动

考察过的包：

- `multiwirth/adreno-3xx-developer-driver`（2020-05 最后更新）；
- `osm0sis/adreno-dev`（Magisk 安装器前端，实际塞的是 Qualcomm 给 Nexus 5/6 的 2015–2016 包）。

实测版本：

```
OpenGL ES 3.0 V@145.0 AU@  (GIT@I9e7a63e7c4)     <- 社区包，2016-06
OpenGL ES 3.0 V@269.0 AU@  (GIT@Ia9da49eece)     <- 本机，2018-12
```

固件对比：

| 文件 | 社区包 md5 | 本机 md5 | 结论 |
|---|---|---|---|
| `a330_pfp.fw` | `d8b8333e3970aa2913d11ebb9470a7fc` | 同左 | 逐字节相同 |
| `a330_pm4.fw` | `71ce5efe6aafc8393c135b333d495c3d` | 同左 | 逐字节相同 |

社区包比本机旧两年，固件没有任何新内容。换上去只会降级，路线关闭。

## 2. 用 HWC 硬件合成“优化跟手度”

`dumpsys SurfaceFlinger` 的 SDM 段落：

```
device type: 0
state: 1, vsync on: 0, max. mixer stages: 0
num configs: 1, active config index: 0
res:480 x 800, dpi:320.84 x 317.50, fps:60

| Idx |  Comp Type  | Split | WB |  Pipe  |    W x H    | Format
|   5 |  GPU_TARGET | Comp-1 |  - | 0x0001 |  480 x  800 | RGBA_8888
```

5 个图层全部 `Client/Client`，HWC 只输出一个 `GPU_TARGET` 层，`max. mixer stages: 0`。这是该平台 vendor HWC 的既定策略：SF 用 GPU 合成一张 480×800 的 target，HWC 只负责送屏，没有可用的叠加层。

不是 GSI 造成的故障，也不是能靠属性回收的优化项。这台机器本来就只能这么合成。

## 3. 给 `libOmxVdec.so` 打二进制补丁

早期做过 `vdec_nativehandle`：修改 `/vendor/lib/libOmxVdec.so`，让 8.1 的 H.264 解码器不再拒绝 Android 9 ACodec 发来的 `allocateNativeHandle` 输出口参数。

- 能工作，但最终发现真正的会话失败点是 DPB/OPB split；
- 属性 `vendor.vidc.disable.split.mode=1` 已足够，不需要改二进制；
- 两个一起用会互相掩盖问题，排障困难。

结论：**不要再叠这个补丁**。保留记录，不纳入发布。

## 4. 改设备树 `st,enable-int`

LIS2DS12 的设备树节点原本是 `st,enable-int=0`。早期把它改成 1 并刷 boot，确实能出数据。

但后来验证：**原厂 boot + 模块写 `0x23=0x01` 同样出数据**。也就是说 DT 那一步不是必需的，刷 boot 只是多一个风险。该补丁已从方案中删除。

## 5. 强制软解

`vdec_swonly` 覆盖 `/vendor/etc/media_codecs.xml`，禁用 8.1 的 qcom 硬解组件，让 `OMX.google.*` 接管。

- 作为“先让视频能放”的临时手段有效；
- 但它会让硬解永远不生效，看起来像“修硬解的模块没用”；
- 功耗和 1080p 性能都明显更差。

结论：硬解修好后必须移除。它与 `vendor.vidc.disable.split.mode=1` 不是互补关系。

## 6. 同时装 `vdec_hwfix`

`vdec_hwfix` 是更早的独立模块，设置的也是 `vendor.vidc.disable.split.mode=1`。与本仓库的 `901si_gsi_fixes` 二选一，不要同时装——两个模块抢同一组属性，行为不可预期。

## 7. 认为“buffer age 是驱动新加的扩展”

早期猜测“V@269 新增了 `EGL_EXT_buffer_age` 但实现有误”。设备实测该扩展**不存在**，只有 `EGL_KHR_partial_update`。真正机理见 [01-buffer-age.md](01-buffer-age.md)。

## 8. 换 GPU 驱动修硬解

硬解走 venus 固件 + V4L2 + OMX，Adreno/KGSL 只负责画上屏。换 GPU blob 对“OMX 会话建立失败”零影响。

## 9. 用 `accelerometer_rotation=0` 关传感器

无效。Nova 桌面和 system_server 会一直订阅方向；要关必须 `echo 0 > /sys/bus/i2c/devices/1-001d/enable`。

## 10. 认为“数据来自驱动轮询”

错误。没有 INT1 中断就没有数据；芯片寄存器在更新不等于驱动收到了样本。
