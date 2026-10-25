# 01 · HWUI 缓冲代龄与闪屏

对应修复：`modules/901si_gsi_fixes`（属性 `debug.hwui.use_buffer_age=false`）。

## 现象

下拉通知栏、展开设置里的折叠项、滑动列表时，屏幕顶部出现黑块和上一屏的残影；手指一停就不再闪。录屏能看到，截图不一定能复现。

## 设备实测

```
GPU: Adreno304v1
驱动: OpenGL ES 3.0 V@269.0 AU@ (GIT@Ia9da49eece)，2018-12
EGL 扩展: 有 EGL_KHR_partial_update，没有 EGL_EXT_buffer_age
GPU 固件: a300_pfp.fw 1156 B / a300_pm4.fw 9220 B / a330_pfp.fw 2212 B / a330_pm4.fw 9220 B
```

用 `app_process` 以 root 跑一个最小 EGL 探针（不需要装 APK），连续交换 8 帧并查询 `EGL_BUFFER_AGE_EXT`：

```
INFO has KHR_partial_update=true
INFO has EXT_buffer_age=false
SWAP 0 swapped=true queryOk=true bufferAge=0
SWAP 1..7 swapped=true queryOk=true bufferAge=2      <- 恒定为 2
```

驱动不是报错，而是**回答了一个值**，所以框架会相信它。

## AOSP 9 的判断逻辑

`frameworks/base/libs/hwui/renderthread/EglManager.cpp`：

```c
// line 154-159
EglExtensions.bufferAge =
        extensions.has("EGL_EXT_buffer_age") || extensions.has("EGL_KHR_partial_update");
EglExtensions.setDamage = extensions.has("EGL_KHR_partial_update");
```

```c
// line 119-123
if (Properties::useBufferAge && EglExtensions.bufferAge) {
    mSwapBehavior = SwapBehavior::BufferAge;
} else {
    mSwapBehavior = SwapBehavior::Preserved;
}
```

```c
// line 391-403
case SwapBehavior::BufferAge:
    EGLint bufferAge;
    eglQuerySurface(mEglDisplay, surface, EGL_BUFFER_AGE_EXT, &bufferAge);
    return bufferAge;   // 返回值没有检查
```

关键点：**只要驱动声明 `EGL_KHR_partial_update`，HWUI 就认为它支持 buffer age**，不需要 `EGL_EXT_buffer_age`。本机正是这种情况。

## 为什么叠加成“残影 + 黑块”

SurfaceFlinger 在这台机器上关闭了三缓冲（`DISABLE_TRIPLE_BUFFERING`），只有两个缓冲。HWUI 按 `bufferAge=2` 计算“哪些像素可以复用”，下发 `eglSetDamageRegionKHR` 只重画脏矩形。两帧前的旧内容因此被保留下来，表现为上一屏的残影和未初始化区域的黑块。

手指停止后不再产生新的 damage，旧的合成结果被整屏呈现，所以“一停就不闪”。

## 修复

`post-fs-data.sh`：

```sh
resetprop debug.hwui.use_buffer_age false
```

HWUI 回落到 `SwapBehavior::Preserved`，`queryBufferAge()` 返回 1（整屏都脏），不再走局部更新。`use_partial_updates` 本身仍是 true，但不再有 buffer age 可用。

代价：每帧多画一点。480×800 下无感。

## 尚未完全定论的一环

到底是：

- (a) 驱动回报的 age 值不对；还是
- (b) 驱动对 `eglSetDamageRegionKHR` 只重画了部分区域。

区分方法：只设 `debug.hwui.use_partial_updates=false`、保留 `use_buffer_age=true`。若不再闪，罪在 (b)；若仍闪，罪在 (a)。本次没有继续做这个区分，因为关闭 buffer age 已经稳定消除症状。

## 边界

- 这是**设备/驱动特定**的规避。其它 GPU 如果 buffer age 正常，关掉它会失去局部更新优化、增加功耗。
- 不要试图通过换社区 Adreno 驱动解决：那些包更旧，固件逐字节相同，见 [08-dead-ends.md](08-dead-ends.md)。
- 不要把这条属性写进通用 GSI 补丁；只在这颗 Adreno 304 + V@269 驱动上用。
