# 04 · LIS2DS12 中断路由实验

对应修复：`modules/lis2ds12_int`（`CTRL4(0x23)=0x01`）。

## 结论

数据通路断在“数据就绪中断从未被路由到 INT1”。写 `CTRL4(0x23)=0x01` 即可；必须是 `0x23`，不能是 `0x22`。

## 硬件/软件栈

- 传感器：ST LIS2DS12，I2C 地址 `1-001d`，`WHO_AM_I(0x0F)=0x43`；
- 同总线：`stk3x1x`（距离/光线）、`gt1x`（触摸）；
- 内核驱动：`lis2ds12_acc`（3.18.71，原厂 2020-04-09 构建）；
- 输入节点：`/dev/input/event2` = `lis2ds12-accel`（主节点，ABS 只在这里）、`event3` = `lis2ds12-irq1-input`；
- vendor HAL：`/vendor/lib/sensors.native.so`，与 LineageOS vendor 镜像内的同一文件逐字节相同；
- 原厂 8.1 system 的 `/lib/hw` 里没有任何传感器 HAL，只有 audio/keystore/hwbinder/hidl.memory。因此原厂也走同一个 vendor HAL、同一份内核和设备树，**原厂 8.1 也没有自动旋转**。

## 关键观测

1. 芯片在采样：`CTRL1(0x20)=0x31`（ODR 50 Hz），`0x28–0x2D` 实时变化（平放 Z≈+1.0g）。
2. 中断寄存器全 0：`CTRL3(0x22)=0x00`、`CTRL4(0x23)=0x00`、`CTRL5(0x24)=0x00`、`MD1_CFG(0x3D)=0x01`（驱动置的）、`MD2_CFG(0x3E)=0x00`。
3. `/proc/interrupts` 的 `160: msmgpio 58 lis2ds12_acc_irq1` 计数恒 0；GPIO58 恒高。
4. 设备树节点 `/soc/i2c@78b5000/lis2ds12@1d`：`interrupts=<58 0x2002>`（下降沿）、`st,enable-int=0`、`st,gpio-int1=<&tlmm 58 2>`、pinctrl `lis2ds12_default` 引脚 58 内部上拉。
5. 驱动的函数表有 `act_int_set/ff_int_set/set_wtm_int`（活动/自由落体/水位中断），但**没有配置 DRDY→INT1 的路径**。

## 寄存器扫描

方法：每次先把 `enable` 置 0 再置 1（芯片断电重上电，等同开机姿态），写入被测寄存器，等 1 秒，测 3 秒内 IRQ 增量与 `event2` 的 ABS_X 条数。

| 寄存器 | 位 | IRQ/3s | ABS_X/3s | 说明 |
|---|---|---|---|---|
| 0x22 CTRL3 | 0x01 | 1171 | 131 | 有数据，390 次/秒伪中断 |
| 0x22 | 0x02 | 1179 | 125 | 同上 |
| 0x22 | 0x10 | 841 | 134 | 280 次/秒 |
| 0x22 | 0x20 | 820 | 119 | 273 次/秒 |
| 0x22 | 0x04/0x08/0x40/0x80 | 0 | 0 | 无效 |
| **0x23 CTRL4** | **0x01** | **164** | **108** | **≈55 次/秒，一样本一脉冲，正确** |
| 0x23 | 其它位 | 0 | 0 | 无效 |
| 0x3D MD1_CFG | 全部位 | 0 | 0 | 无效 |
| 0x3E MD2_CFG | 全部位 | 0 | 0 | 无效 |

## CPU 对照

20 秒窗口，`/proc/stat` 空闲占比与 system jiffies：

| 配置 | idle% | sys | IRQ/20s | ABS_X/20s |
|---|---|---|---|---|
| 传感器关闭（enable=0） | 93 | 354 | 0 | 0 |
| `0x22=0x01` | 83 | 925 | 4997 | 910 |
| `0x23=0x01` | 92 | 393 | 999 | 864 |
| `0x23=0x01` 复测 | 92 | 366 | 998 | 878 |
| `0x22=0x10` | 80 | 1005 | 6131 | 923 |

结论：只有 `0x23=0x01` 同时满足“中断率 = 采样率”和“数据完整”。

## 为什么 0x22 会风暴

`0x22` bit0 是**锁存型**输出：芯片拉低 INT1 后不会自己释放，直到有人读状态寄存器。驱动不读状态寄存器，于是 GPIO 中断在锁存期间被反复重入，产生约 8 倍于采样率的伪中断（390/s vs 50/s）。这就是“刷完 GSI 后界面卡顿、设置列表往回弹”的元凶。

`0x23` bit0 是**脉冲型**，每个样本恰好一个中断。

## 最终实现

`modules/lis2ds12_int/service.sh`：

```sh
S=/sys/bus/i2c/devices/1-001d
while true; do
  [ -f /data/local/tmp/lis2ds12_off ] && exit 0
  e=$(cat $S/enable)
  if [ "$e" = "1" ]; then
    echo 0x23 > $S/reg_addr
    v=$(cat $S/reg_value)
    if [ "$v" != "0x01" ]; then
      echo 0x23 > $S/reg_addr
      echo 1 > $S/reg_value
    fi
  fi
  sleep 1
done
```

- 屏幕熄灭/芯片下电后寄存器归零，下次 `enable=1` 后 1 秒内补写；
- 数据率仍为 50 Hz（ODR `0x31`），不改 CTRL1；
- 不改设备树、不改内核、不替换 HAL。

## 验证

```sh
S=/sys/bus/i2c/devices/1-001d
adb shell su -c "grep lis2ds12 /proc/interrupts; sleep 5; grep lis2ds12 /proc/interrupts"
# 两次计数差约 250（50/s）

adb shell su -c "echo 0x23 > $S/reg_addr; cat $S/reg_value"
# 0x01

adb shell su -c "timeout 3 getevent /dev/input/event2 | grep -c '0003 0000'"
# 约 130（43/s，ABS_X 不是每个样本都有）
```

## 走错的路

- 早期认为要改设备树 `st,enable-int` 0→1 并刷 boot：做过、也能用，但**并非必需**——原厂 boot 加模块写寄存器同样出数据。该补丁已删除，用户不再需要刷 boot。
- 用 `accelerometer_rotation=0` 想“关掉传感器”：无效。Nova 桌面（`OrientationEventListener`）和 system_server（`WindowOrientationListener`）会一直订阅；必须 `echo 0 > .../enable`。
- 观察到“CTRL3=0 时仍有 228–390/s 中断”：假象，是守护进程每 2 秒把 CTRL3 写回 0x01 造成的；真正没人写时中断为 0。
- 认为“数据来自驱动轮询、中断冗余”：错误，没有中断就没有数据。
- vmlinux 反汇编找 DT 属性引用、`vmlinux-to-elf`：无产出，不必再试。

## 关闭

```sh
adb shell su -c 'touch /data/local/tmp/lis2ds12_off'
# 重启后模块不再写寄存器，自动旋转随之失效
```

## 限制

- 采样率固定 50 Hz；要改需同时改 CTRL1，本模块不碰。
- 只在这个 LIS2DS12 + msm8909 集成驱动上验证；其它机型寄存器语义可能相同，但 I2C 路径可能不同。
- 本机没有陀螺仪（只有距离、光线、加速度），指南针/VR/陀螺防抖依旧不可用——硬件不存在，不是没修好。
