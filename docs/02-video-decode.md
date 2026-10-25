# 02 · venus DPB/OPB split 与硬解

对应修复：`modules/901si_gsi_fixes`（属性 `vendor.vidc.disable.split.mode=1`）。

## 现象

任何播放器播 H.264/HEVC 都只有声音、没有画面。软解正常，硬解一开就黑屏；`logcat` 里能看到 OMX 组件报错。

## 关键日志

```
D OMX-VDEC-1080P: DPB mode: split DPB color format: nv12_ubwc OPB color format: nv12
E OMX-VDEC-1080P: Failed to set ext ctrls for opb_dpb: -1
err: HFI_EVENT_SESSION_ERROR
warn: Unsupported bitstream in 00000000
```

## 根因

Android 9 的 ACodec 在建立解码会话时请求 **DPB/OPB 分离模式**：

- DPB = Decoded Picture Buffer，解码参考帧；
- OPB = Output Picture Buffer，送显示的帧；
- split 模式让两者使用不同的颜色格式/缓冲区（这里 DPB 是 `nv12_ubwc`，OPB 是 `nv12`）。

本机 vendor 来自 Android 8.1（2020-04-09 构建），其 venus 固件与 OMX 组件不认识这个模式，设置扩展控件失败后直接销毁会话。

后面那句 `Unsupported bitstream` 是**会话已经被拆掉之后**打出来的尸体报告。此时组件没有有效的会话/缓冲区，任何码流都会被报成“不支持”。这就是最容易把排查带偏的地方：它看起来像“固件读不懂 HEVC”，实际是“会话根本没建起来”。

## 修复

```sh
resetprop vendor.vidc.disable.split.mode 1
```

这是高通 OMX 源码 `omx_vdec_v4l2.cpp` 里已有的开关：置 1 后组件忽略 split 请求，退回 8.1 的合并模式（DPB 与 OPB 共用缓冲）。

属性必须在 `post-fs-data` 阶段、`mediaserver` 启动前设置。运行时再 `setprop` 对已经建立的会话无效，需要重启。

## 验证

```sh
adb shell su -c 'getprop vendor.vidc.disable.split.mode'   # 1
adb shell su -c 'dumpsys media.player | grep -i codec'      # 应出现 OMX.qcom.video.decoder.avc/hevc
```

实测 1080p30 HEVC 流畅；H.264 同样恢复。

## 边界与坑

- 只对“8.1 venus 固件 + Android 9 framework”这个组合需要。新固件本身支持 split，强制关闭会退回合并模式，性能和内存利用略降。
- 不要再叠加早期 `libOmxVdec.so` 二进制补丁（`vdec_nativehandle`）或强制软解 `media_codecs.xml`（`vdec_swonly`）。它们和本属性解决的是同一问题的不同阶段，叠在一起行为不可预期。
- 如果装过 `vdec_hwfix`，它设置的是同一个属性；与本模块二选一即可。
- 修改 `/vendor/etc/media_codecs.xml` 后只重启 `mediacodec` 不够，必须重启 `mediaserver`（`setprop ctl.restart media`）或整机重启。

## 为什么不是 GPU 驱动

硬解走 venus 固件 + V4L2 + OMX 组件，Adreno/KGSL 只负责把解出来的帧画上屏。换 GPU blob 对“会话建立失败”零影响，见 [08-dead-ends.md](08-dead-ends.md)。
