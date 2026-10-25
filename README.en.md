# 901si GSI Fixes

A set of Magisk modules for running an **Android 9 GSI** on the **SoftBank 901si** (same platform as KYV41; Qualcomm msm8909 + Adreno 304). There are five independent modules — install only what you need. Everything is done through Magisk mounts or runtime properties: **no boot image flashing, no partition modification**. Disable a module and reboot to roll back.

> 中文: [README.md](README.md)

## AI assistance disclosure

The code, scripts, documentation and investigation notes in this repository were written with **AI assistance** (a coding agent running in DeepSeek Harness). Every change was actually installed, run and verified on a real device (901si, Android 9 GSI); conclusions are based on device logs and measurements.

AI-generated material can still contain mistakes, stale information, or assumptions that do not hold for your device or OS build. **Before flashing any module, read the source, verify the checksums, and back up your stock images.** You are responsible for any device damage, data loss or malfunction caused by using this repository.

## Why this repository exists

The device shipped with Android 8.1 and its vendor partition is frozen at a build from 2020-04-09. After flashing an Android 9 GSI (tested: phh v23 / LineageOS 16.0) the system boots, but several things break because the 8.1 vendor and the 9 framework disagree:

- the screen flickers, shows black blocks and stale frames;
- video plays audio but no picture;
- the camera freezes after a shot and the photo is never saved;
- auto-rotation never works;
- the red/green status LED stays off, or the green LED stays on after boot;
- VoLTE does not register;
- the stock camera app crashes on launch.

None of these are fixed by flashing another package. Each one had to be traced down to a register, a property, or an 8-byte binary patch. This repo collects the working fixes, their source, the build scripts, and the dead ends.

## Requirements

| Item | Value |
|---|---|
| Device | SoftBank 901si (KYV41 platform), msm8909, Adreno 304 |
| System | Android 9 GSI, A-only, 32-bit (tested: phh v23 / LineageOS 16.0) |
| Stock base | Android 8.1.0, vendor 2020-04-09, kernel 3.18.71 |
| Prerequisites | Rooted with Magisk; `resetprop` and `magiskpolicy` available |
| Not for | 64-bit GSIs, A/B devices, other SoCs, other LED/accelerometer hardware |

The modules are validated only against the baseline above. Other devices with the same SoC can borrow the ideas, but paths, registers and HAL names may differ — do not copy blindly.

## Modules

| Module | Version | Fixes | Release asset |
|---|---|---|---|
| `901si_gsi_fixes` | v1.0 | HWUI flicker/stale frames, venus hardware decoding, JPEG HAL camera abort | `901si-gsi-fixes-v1.0.zip` |
| `lis2ds12_int` | v1.3 | LIS2DS12 data-ready interrupt never routed; auto-rotation dead | `lis2ds12_int-v1.3.zip` |
| `ledlineage` | v1.0 | Vendor LED HAL path missing + SELinux denial; status LED dead | `ledlineage-v1.0.zip` |
| `volte_caf` | v0.1 | CAF IMS stack missing from the GSI; VoLTE cannot register | `volte_caf-v0.1.zip` |
| `stockcam_helpers` | v1.0 | Stock camera missing its event-log provider and gallery component | `stockcam_helpers-v1.0.zip` |

The `SHA256SUMS` file on the Releases page is authoritative. Module versions in the source match the `module.prop` inside each zip.

## Quick start

1. Download the zips you need from [Releases](https://github.com/PDWYX/901si-gsi-fixes/releases).
2. Copy them to the phone.
3. Magisk app → Modules → Install from storage → pick the zip.
4. Reboot.

Or from a shell. Note that on this device an `adb shell su -c` session cannot see `/data/adb`, so use `magisk --install-module`:

```sh
adb push 901si-gsi-fixes-v1.0.zip /data/local/tmp/
adb shell su -c 'magisk --install-module /data/local/tmp/901si-gsi-fixes-v1.0.zip'
adb reboot
```

Recommended order: install `901si_gsi_fixes` first and confirm display/video/camera, then add the others as needed. They do not depend on each other.

## The fixes

### 1. Flicker, black blocks, stale frames (`901si_gsi_fixes`)

**Symptom.** Pulling down the notification shade, expanding a collapsed settings section, or scrolling a list produces black blocks and remnants of the previous frame near the top of the screen. It stops as soon as the finger stops.

**Root cause.** The Adreno 304 driver advertises `EGL_KHR_partial_update`, but `eglQuerySurface(EGL_BUFFER_AGE_EXT)` reports a wrong buffer age (measured: always 2). Android 9's HWUI trusts it and takes the `SwapBehavior::BufferAge` path, reusing old frame contents. Combined with SurfaceFlinger's double buffering (`DISABLE_TRIPLE_BUFFERING`), the stale content becomes visible.

**Fix.** `post-fs-data.sh` sets:

```
debug.hwui.use_buffer_age=false
```

HWUI falls back to `SwapBehavior::Preserved` (full-frame preservation). The cost is a little more drawing per frame, which is invisible at 480×800.

### 2. Video has audio but no picture (`901si_gsi_fixes`)

**Symptom.** Any player decodes H.264/HEVC audio, but the picture is black.

**Root cause.** Android 9's ACodec opens the decoder session in **DPB/OPB split mode**:

```
D OMX-VDEC-1080P: DPB mode: split DPB color format: nv12_ubwc OPB color format: nv12
E OMX-VDEC-1080P: Failed to set ext ctrls for opb_dpb: -1
err: HFI_EVENT_SESSION_ERROR / warn: Unsupported bitstream in 00000000
```

The venus firmware on this device is from the 8.1 era and does not understand that mode, so it tears the session down. The later `Unsupported bitstream` line is emitted **after** the session is already gone — it does not mean the firmware cannot parse the stream, and it sends debugging in the wrong direction.

**Fix.** Set:

```
vendor.vidc.disable.split.mode=1
```

This makes the component fall back to the 8.1 combined mode (DPB and OPB share buffers). It is an existing switch in Qualcomm's `omx_vdec_v4l2.cpp`. After this, `OMX.qcom.video.decoder.avc/hevc` work again; 1080p30 HEVC plays smoothly.

### 3. Camera freezes and photos are not saved (`901si_gsi_fixes`)

**Symptom.** Preview and video recording work. After pressing the shutter the preview freezes and no new file appears in `/sdcard/DCIM/Camera`.

**Root cause.** The capture actually succeeds (JPEG encoding completes), but when the HAL releases the session, `QImageHybridEncoder::ReleaseSession()` destroys the same mutex a second time. Android 8.1's bionic merely returns an error; Android 9's FORTIFY aborts:

```
F/libc: FORTIFY: pthread_mutex_destroy called on a destroyed mutex
F/libc: Fatal signal 6 (SIGABRT) in tid 839 (OMX_ImgEnc)
```

The camera provider process dies on the spot, so the preview freezes and the photo is never written.

**Fix.** Replace the two `bl os_mutex_destroy` / `bl os_cond_destroy` calls in `ReleaseSession` with Thumb NOPs (`00 BF 00 BF`). Only 8 bytes of a 167,620-byte library change. See [`patches/jpeg/`](patches/jpeg/).

The module's `customize.sh` checks the md5 of `/vendor/lib/libmmqjpeg_codec.so`:

| Build | md5 |
|---|---|
| Stock | `73d3594e71ed0866194ecaab845b781b` |
| Patched | `d6911e58ee5a2b2146022041152066b6` |

If it does not match, the camera patch is **skipped automatically** and only the two property fixes are installed — it will not corrupt the camera HAL.

### 4. Auto-rotation never works (`lis2ds12_int`)

**Symptom.** The auto-rotate toggle turns on, but the screen never rotates. `dumpsys sensorservice` shows `lis2ds12-accel` as `status: active` but no samples arrive.

**Root cause.** The LIS2DS12 data-ready interrupt routing register **CTRL4 (0x23) is never written**, so INT1 (GPIO58) never fires and the kernel driver receives no samples. The chip itself samples fine (reading 0x28–0x2D directly shows changing values). The stock 8.1 build uses the same vendor HAL, kernel and device tree, so **stock 8.1 has no auto-rotation either** — the GSI did not break it.

**Fix.** The standalone module's `service.sh` checks once per second and, when `enable=1` and `0x23 != 0x01`, writes `0x23=0x01` (pulsed, one interrupt per sample, 50 Hz).

**Important.** It must be `0x23`, not `0x22`. `0x22` bit 0 is a latched output and produces roughly **390 false interrupts per second** (measured: about 1.5 CPU cores burned, visible UI stutter and list bounce); `0x23` bit 0 is pulsed and gives exactly 50 per second. See [`docs/04-accelerometer.md`](docs/04-accelerometer.md) for the register experiments.

Disable it with `touch /data/local/tmp/lis2ds12_off` and reboot.

### 5. Red/green status LED dead (`ledlineage`)

**Symptom.** After flashing a GSI the status LED never lights; on boot the green LED may stay on forever.

**Root cause.** Two things at once:

1. The vendor LED HAL `lights.msm8909.so` hardcodes `/sys/class/leds/{red,green,blue}/brightness`, while this device's driver only exposes `/sys/class/leds/slg4ax42959v_led/{redled,greenled,blueled,poweron}`;
2. The `hal_light_default` domain has no write permission on sysfs — `rc=-13` in `logcat`.

**Fix.** `post-fs-data.sh` mounts a tmpfs over `/sys/class/leds`, bind-mounts the original entries (backlight, flashlight, etc.) back in, creates `red/green/blue` compatibility nodes with `chmod 666`, and grants `hal_light_default` access via `magiskpolicy --live`. `daemon.sh` translates the HAL's 0–255 brightness into the driver's pattern `0/1` and keeps `poweron=1`.

**Safety valve.** If `lcd-backlight/brightness` is unreadable after the overlay, the script immediately `umount`s and rolls back, so the screen cannot be left dark.

### 6. VoLTE (`volte_caf`)

**Background.** The vendor IMS HIDL services are present (`imsradio0`, `imscmservice` are online), but the system side lacks `org.codeaurora.ims`; `framework-res` has `config_ims_package=""` and `config_dynamic_bind_ims=false`, so `ImsResolver` binds nothing. Changing build.prop switches alone does nothing.

**Fix.**

1. Put phh's recompiled `ims.apk` (`org.codeaurora.ims`, testkey-signed, `sharedUserId=android.uid.phone`) into `/system/priv-app/ims/`;
2. Extract **all 38 .so files** from the APK into `/system/priv-app/ims/lib/arm/`;
3. Ship a preinstalled RRO `com.dsh.ims.overlay` that overrides `config_ims_package` / `config_dynamic_bind_ims`; the RRO must live in `/system/app/`;
4. Set `persist.dbg.ims_volte_enable` and friends; after boot enable the overlay and restart `com.android.phone`.

Measured on China Mobile: `REQUEST_IMS_REGISTRATION_STATE ... state: 2 radioTech: 14`; calls go over IMS and stay on LTE.

### 7. Stock camera (`stockcam_helpers`)

The stock camera is `jp.co.seiko.kidsphone` (Japanese label "カメラ"), not an AOSP camera. It is not in the GSI and must be extracted from your own stock image. Installed as-is on a GSI it crashes on two missing dependencies:

| Crash | Cause | Fix |
|---|---|---|
| `Unknown URL content://com.ssol.eventlog/eventlog` | The stock `EventLog` provider is OEM platform-signed and absent from the GSI | Install a same-authority stub `com.dsh.eventlogstub` |
| `ActivityNotFoundException: {org.codeaurora.gallery/...}` | The stock SnapdragonGallery conflicts with the GSI's Gallery2 permissions and cannot be installed | Install a package/activity shim `org.codeaurora.gallery` that forwards to `com.android.gallery3d/.app.GalleryActivity` |

The module installs both helper APKs at boot and grants the camera CAMERA / RECORD_AUDIO / READ / WRITE_EXTERNAL_STORAGE permissions. **The camera APK itself is not redistributed here**; see [`docs/07-stock-camera.md`](docs/07-stock-camera.md).

## Known pitfalls (read this)

This section matters more than the list of fixes. Every item below was hit for real and can cost an evening.

| # | Pitfall | Consequence | Do this instead |
|---|---|---|---|
| 1 | Writing `0x22=0x01` to the accelerometer | ~390 false interrupts/s; UI stutter and list bounce | Write only `0x23=0x01` (pulsed) |
| 2 | Writing `slg4ax42959v_led/trigger` or the global `brightness` | **Kernel panic and reboot** (reproduced twice) | Write only `redled/greenled/blueled` pattern `0/1`; keep `poweron=1` |
| 3 | Leaving the 38 VoLTE .so files inside the APK | `UnsatisfiedLinkError: libimsmedia_jni.so`; `com.android.phone` crash loop | Extract them to `system/priv-app/ims/lib/arm/` |
| 4 | Installing the IMS RRO with `pm install` | `must be signed with the platform certificate` | Preinstall the RRO into `/system/app/` (preinstall does not check the signature) |
| 5 | Treating `Unsupported bitstream` as a codec problem | Endless decoder/player changes, completely wrong direction | Look for the earlier `DPB mode: split` and `HFI_EVENT_SESSION_ERROR`; the later line is post-mortem noise |
| 6 | Assuming auto-rotation needs a DT change / boot flash | Pointless boot flashing, problem remains | Only CTRL4 `0x23=0x01` is needed; the DT `st,enable-int` change is not required |
| 7 | Swapping in a community Adreno 3xx driver | The community drivers are older (V@145 vs V@269 here) and their firmware is byte-identical; pure downgrade | Do not swap. HWC showing Client/Client is SDM's single-GPU_TARGET policy, not a fault |
| 8 | Applying the early `libOmxVdec.so` binary patch | Ultimately unnecessary; the property fix is enough | Use `vendor.vidc.disable.split.mode=1`; do not stack binary patches |
| 9 | Running `vdec_hwfix` and `901si_gsi_fixes` together | Both fight over the same properties; unpredictable behaviour | Keep only one; this repo's module already sets the property |
| 10 | A "force software decode" `media_codecs.xml` override is still installed | Hardware decode will not engage; looks like the module does nothing | Remove the software-decode module first, then verify |
| 11 | Copying `debug.hwui.use_buffer_age=false` to another GSI/device | GPUs with correct buffer age lose partial-update optimisation and burn more power | Use only on this Adreno 304 + driver combination |
| 12 | Forcing `disable.split.mode=1` on firmware that supports split | It works but falls back to combined mode, with slightly worse performance/memory use | Do not set it on newer firmware; this device's 8.1 venus needs it |
| 13 | Moving the stock camera APK to a non-phh GSI | Different platform signature; features relying on system permissions/properties may break | Stay on a phh-based GSI, or re-sign/adjust permissions yourself; no camera APK is bundled |
| 14 | Installing `eventlogstub` on stock 8.1 that still has `EventLog` | Authority conflict; provider install fails | GSI only; stock does not need it |
| 15 | Installing `gallerybridge` where stock SnapdragonGallery exists | Package name conflict | GSI only (with Gallery2) |
| 16 | Expecting a gyroscope | Compass/VR/stabilisation will never work; mistaken for "not fixed yet" | This device has only proximity, light and accelerometer — the hardware does not exist |
| 17 | Touching `/data/adb` inside `adb shell su -c` | That root session cannot see the directory; scripts report "module not found" | Use `adb shell su -c 'magisk --install-module ...'` or install from the Magisk app |
| 18 | Not rebooting after install | `resetprop` runs in post-fs-data and the overlay is enabled at boot | Reboot. On first VoLTE boot `com.android.phone` is restarted once more |
| 19 | Using the 32-bit VoLTE package on a 64-bit GSI | IMS will not start or crashes | On 64-bit use [khrj/volte-fix](https://github.com/khrj/volte-fix) `64bit/ims` |
| 20 | Re-signing the `stockcam_helpers` APKs and installing over the old ones | Signature mismatch; `pm install -r` fails | Uninstall the old package first, or keep the bundled CN=dsh-signed build |
| 21 | Flashing these modules on A/B or 64-bit devices | Paths/libraries/properties do not match; may not boot | A-only 32-bit msm8909 901si only |
| 22 | Redistributing the vendor binaries as if they were open source | Copyright/licence problem | Personal repair use only; see [NOTICE.md](NOTICE.md) |

### Why writing the LED node reboots the device

On this device `slg4ax42959v_led/trigger` and `slg4ax42959v_led/brightness` are not ordinary writable nodes; writing them panics the kernel. The module only touches:

- `slg4ax42959v_led/poweron`
- `slg4ax42959v_led/redled`
- `slg4ax42959v_led/greenled`
- `slg4ax42959v_led/blueled`

If you edit the scripts, do **not** "helpfully" add `trigger` or global brightness.

### Why not the existing solutions

- Community Adreno 3xx drivers (multiwirth / osm0sis) are V@145.0 (2016); this device runs V@269 (2018-12), and `a330_pfp.fw` / `a330_pm4.fw` are byte-identical. Swapping is a downgrade — that route is closed.
- Earlier attempts included an `libOmxVdec.so` binary patch, a DT `st,enable-int` change, and a forced-software `media_codecs.xml`. All turned out to be unnecessary or inferior. Records are in [`docs/08-dead-ends.md`](docs/08-dead-ends.md).

## Verification

```sh
# Properties
adb shell su -c 'getprop debug.hwui.use_buffer_age'          # false
adb shell su -c 'getprop vendor.vidc.disable.split.mode'    # 1
adb shell su -c 'getprop persist.dbg.ims_volte_enable'      # 1

# Accelerometer: about 250 interrupts in 5 s (50 Hz)
adb shell su -c 'grep lis2ds12 /proc/interrupts; sleep 5; grep lis2ds12 /proc/interrupts'

# Register
adb shell su -c 'echo 0x23 > /sys/bus/i2c/devices/1-001d/reg_addr; cat /sys/bus/i2c/devices/1-001d/reg_value'
# 0x01

# LED nodes
adb shell su -c 'ls /sys/class/leds/red /sys/class/leds/green'

# IMS registration (state: 2 = registered)
adb shell su -c 'dumpsys telephony.registry | grep -i ims'
```

Or run `tools/verify.sh` (needs adb + root).

## Building from source

```sh
# Rebuild all five Magisk modules -> dist/
tools/build-release.sh

# Rebuild the two camera helper APKs (needs the Android SDK)
ANDROID_HOME=/path/to/android-sdk tools/build-apks.sh

# Rebuild the VoLTE RRO
ANDROID_HOME=/path/to/android-sdk tools/build-overlay.sh
```

Release artifacts are not committed; they are hosted on GitHub Releases. `dist/` and `build/` are in `.gitignore`.

## Repository layout

```
.
├── modules/                 # sources for the five modules (zip contents)
│   ├── 901si_gsi_fixes/
│   ├── lis2ds12_int/
│   ├── ledlineage/
│   ├── stockcam_helpers/
│   └── volte_caf/
├── patches/jpeg/            # 8-byte JPEG HAL patch + notes
├── apk-src/                 # Java sources for the two camera helper APKs
├── overlay-src/ims/         # VoLTE RRO source
├── tools/                   # packaging, building, extraction, verification
├── docs/                    # per-issue root-cause and experiment notes
├── README.md                # Chinese
├── README.en.md             # English
├── NOTICE.md                # third-party components and licences
└── LICENSE                  # MIT (repository scripts/sources only)
```

## Rollback

- General: disable the module in the Magisk app, then reboot;
- or `touch /data/adb/modules/<id>/disable` and reboot;
- or `rm -rf /data/adb/modules/<id>` and reboot.

The modules do not modify partitions: properties are runtime `resetprop`, files are Magisk magic mounts, and `ledlineage`'s tmpfs/bind mounts disappear on reboot. The only thing left in `/data` is the two APKs installed by `stockcam_helpers`; uninstall them with `pm uninstall com.dsh.eventlogstub org.codeaurora.gallery` if no longer needed.

## Research notes

- [01 · HWUI buffer age and flicker](docs/01-buffer-age.md)
- [02 · venus DPB/OPB split and hardware decode](docs/02-video-decode.md)
- [03 · JPEG HAL double mutex destroy](docs/03-camera-jpeg.md)
- [04 · LIS2DS12 interrupt routing experiments](docs/04-accelerometer.md)
- [05 · SLG4AX status LED and SELinux](docs/05-led.md)
- [06 · CAF IMS and VoLTE](docs/06-volte.md)
- [07 · Stock camera dependencies](docs/07-stock-camera.md)
- [08 · Dead ends and rejected approaches](docs/08-dead-ends.md)
- [09 · Earlier work on the stock 8.1 image](docs/09-legacy-stock-8.1.md)

## Credits

- [phhusson/treble_experimentations](https://github.com/phhusson/treble_experimentations) — GSI and platform-signature baseline;
- [khrj/volte-fix](https://github.com/khrj/volte-fix) — CAF IMS stack rebuilt for phh GSIs;
- AOSP / LineageOS — HWUI, ACodec, Gallery2;
- Magisk / topjohnwu — modules, `resetprop`, `magiskpolicy`.

## Licence

Scripts and original Java sources in this repository are MIT-licensed; see [LICENSE](LICENSE).
Vendor binaries included in the modules (`libmmqjpeg_codec.so`, `ims.apk` and its `.so` files, the RRO, etc.) remain the property of their respective owners, are **not** covered by MIT, and are included only for personal device repair. See [NOTICE.md](NOTICE.md).

---

**Disclaimer.** These changes act directly on the camera HAL, the video decoder, IMS and the LED driver, and can destabilise or brick the device. Make sure you have a stock image and a recovery path first. Provided "as is" under the MIT licence, without warranty of any kind.
