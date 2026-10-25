# libmmqjpeg_codec.so 补丁

原厂 Android 8.1 的 JPEG HAL 在释放编码会话时会二次销毁同一个互斥锁。
Android 8.1 的 bionic 只是返回错误码，Android 9 的 FORTIFY 则直接 abort：

```
F/libc: FORTIFY: pthread_mutex_destroy called on a destroyed mutex
F/libc: Fatal signal 6 (SIGABRT) in tid 839 (OMX_ImgEnc)
```

相机 provider 进程随即死亡：预览定格、照片不落盘。

补丁把 `QImageHybridEncoder::ReleaseSession()` 里的两条 BL 指令
（调用 `os_mutex_destroy` / `os_cond_destroy`）改成 Thumb NOP：

| 文件偏移 | 原字节 | 补丁后 |
|---|---|---|
| `0x20742` | `e8 f7 1a ec` | `00 bf 00 bf` |
| `0x20752` | `e8 f7 18 ec` | `00 bf 00 bf` |

167620 字节的文件只改 8 字节。

```sh
python3 patch_mmqjpeg.py /path/to/stock/libmmqjpeg_codec.so ./libmmqjpeg_codec.so
```

| 版本 | md5 |
|---|---|
| 原厂 | `73d3594e71ed0866194ecaab845b781b` |
| 补丁版 | `d6911e58ee5a2b2146022041152066b6` |

只对上述 md5 的库有效；模块的 `customize.sh` 也会做同样的校验，
版本不匹配时自动跳过相机补丁，只安装两个属性修复。
