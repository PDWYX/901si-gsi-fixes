# 05 · SLG4AX 状态灯与 SELinux

对应修复：`modules/ledlineage`。

## 现象

原厂 8.1 有一红一绿两颗状态灯；刷 Android 9 GSI 后完全不亮，开机还会一直亮绿灯。

## 两件事同时挡着

`logcat` 里灯 HAL 一直在被调用：

```
D qdlights: set_speaker_light_locked mode=0, colorRGB=6400FF00, onMS=0, offMS=0, rc=-13
I avc: denied { read write } for name="redled" dev="sysfs" ... scontext=u:r:hal_light_default:s0
```

1. **路径不存在**。厂商灯 HAL `lights.msm8909.so` 写死 `/sys/class/leds/{red,green,blue}/brightness`（还有 `blink`、`breath`、`delay_on`、`delay_off`），而本机驱动只提供 `/sys/class/leds/slg4ax42959v_led/{redled,greenled,blueled,poweron}`。
2. **SELinux 不放行**。`hal_light_default` 域对 sysfs 没有写权限，路径对了也是 `rc=-13 (EACCES)`。

那个 `rc=-13` 说明原厂 8.1 上这套通知灯大概率也是废的（vendor sepolicy 从未给过写权限）；原厂能看到的灯是内核自己的充电灯/开机默认绿灯。

## 做法

### post-fs-data.sh（开机早期，一次）

1. 把 `/sys/class/leds` 换成 tmpfs；
2. 原来每一项（`lcd-backlight`、`torch-light0`、`button-backlight`、`flashlight`、`mmc0::`…）按 `readlink -f` 的真实路径 `mount --bind` 放回去，标签和权限不变；
3. 新建 `red/ green/ blue/` 三个目录，各放 `brightness blink breath delay_on delay_off` 五个普通文件，`chmod 666`（HAL 以 `system` uid 1000 运行）；
4. 用 `magiskpolicy --live` 给 `hal_light_default` 加 `tmpfs file read/write`、`tmpfs dir search`；
5. 安全阀：若 `lcd-backlight/brightness` 读不到，立刻 `umount` 回滚，绝不留下黑屏。

### service.sh + daemon.sh

把 HAL 写的 0–255 亮度翻译成驱动认的 pattern 值，并把 `poweron` 置 1。

## 为什么需要翻译

驱动 `SLG4AX42959V` 的通道节点只认两个值：

| 写入 | 效果 |
|---|---|
| `0` | 灭 |
| `1` | 常亮 |
| `2/3/255/…` | 能回显 `patternid:N`，但物理上不亮 |

HAL 送的是亮度（255 = 全亮）。另外驱动有总闸 `poweron`：`poweron=0` 时通道 pattern 怎么写都不亮（这也是“开机一直亮绿灯”的来源——驱动默认把绿灯置 1）。所以守护脚本保持 `poweron=1`，`brightness>0 → 1`、`=0 → 0`，启动时先把三路清零。

## 谁的灯

| 灯 | 系统里的负责人 | 模块的角色 |
|---|---|---|
| 充电灯（红/绿） | `BatteryService` → `LightsManager` | 只翻译 |
| 通知灯 | `NotificationManagerService`（受设置里“通知灯”开关控制） | 只翻译 |
| 屏幕背光 / 手电筒 | `LightsService` | 路径原样透传，未改动 |

模块不读电量、不监听通知，判断全在系统里；守护进程每 0.15 秒读三个 4 字节文件，功耗可忽略。

## 绝对不能写

在这台机器上，以下节点写入会**内核崩溃、设备重启**（实测两次）：

- `/sys/class/leds/slg4ax42959v_led/trigger`
- `/sys/class/leds/slg4ax42959v_led/brightness`

模块只碰：

- `poweron`
- `redled`
- `greenled`
- `blueled`

如果你改脚本，不要“顺手”加 `trigger` 或全局亮度。

## 验证

```sh
adb shell su -c 'cat /data/adb/ledlineage/boot.log'
# overlay ok, backlight=255
# ... supervising /data/adb/modules/ledlineage/daemon.sh

adb shell su -c 'ls /sys/class/leds/red /sys/class/leds/green'
# brightness blink breath delay_on delay_off

adb shell su -c 'cat /sys/class/leds/slg4ax42959v_led/poweron'   # 1
```

触发充电/通知后看灯是否亮；不要用 echo 255 写 brightness 去测，那会写坏。

## 回滚

Magisk 里关模块重启，或 `touch /data/adb/modules/ledlineage/disable`，或删除模块目录。tmpfs 与 bind mount 都是内存态，重启即消失，不留磁盘改动。

## 限制

- 本机只有红、绿两颗灯，没有蓝灯；`blue` 节点写入无害但不发光。
- 只实现**常亮**语义；通知灯要求“闪烁”时目前是常亮（HAL 的 `blink`/`delay_on` 尚未接）。
- 只适用于 `slg4ax42959v` 这颗灯控，sysfs 路径硬编码。
