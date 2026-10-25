# NOTICE — third-party components and licensing

This repository is a personal repair project for a single device (SoftBank
901si / KYV41 platform, msm8909). It is **not** an official product and is not
affiliated with SoftBank, Sharp, Qualcomm, Google, or any ROM project.

The MIT licence in [LICENSE](LICENSE) covers only the original scripts,
documentation and Java sources written for this repository.

## Components under their own licences

| Component | Where | Licence / origin |
|---|---|---|
| `org.codeaurora.ims` (`ims.apk`) and its 38 `.so` files | `modules/volte_caf/system/priv-app/ims/` | Code Aurora Forum IMS stack, Apache License 2.0. The APK here was rebuilt for phh-based GSIs by the [khrj/volte-fix](https://github.com/khrj/volte-fix) project (testkey-signed). |
| AOSP / LineageOS code referenced in the notes | `docs/` | Apache License 2.0 (AOSP), respective LineageOS licences. Only short excerpts are quoted for analysis. |
| Magisk | module format, `resetprop`, `magiskpolicy` | Magisk is GPL-3.0 by topjohnwu. No Magisk source is included here. |
| Android SDK build tools | used by `tools/` | Android SDK Licence. Not redistributed. |

## Proprietary vendor binaries

These files are **not** open source. They are copied from, or patched versions
of files from, the device's own vendor partition. They are included only so the
device owner can repair their own hardware, and they must not be treated as
MIT-licensed or redistributed commercially.

| File | Origin | Nature |
|---|---|---|
| `modules/901si_gsi_fixes/system/vendor/lib/libmmqjpeg_codec.so` | Stock `/vendor/lib/libmmqjpeg_codec.so` | Qualcomm JPEG encoder; 8 bytes patched to NOP out a double mutex destroy |
| `modules/volte_caf/system/priv-app/ims/ims.apk` | Code Aurora IMS, rebuilt | Apache-2.0 source, testkey-signed build |
| `modules/volte_caf/system/priv-app/ims/lib/arm/*.so` | Same APK | Qualcomm/CAF IMS native libraries |
| `modules/volte_caf/system/app/*.apk` | Built from `overlay-src/ims` | Original RRO, MIT |

## Not included

- The stock camera APK (`jp.co.seiko.kidsphone`) — extract it from your own
  stock image; see `docs/07-stock-camera.md`.
- The stock boot/system/vendor images.
- Any signing keys, keystores or GitHub tokens.

## Trademarks

Qualcomm, Snapdragon, Adreno, Android, Magisk and all other names are
trademarks of their respective owners. Use of a name does not imply endorsement.
