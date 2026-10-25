#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
给 901si 原厂 /vendor/lib/libmmqjpeg_codec.so 打“防二次销毁互斥锁”补丁。

背景：QImageHybridEncoder::ReleaseSession() 会第二次调用
os_mutex_destroy/os_cond_destroy。Android 9 的 bionic FORTIFY 直接 abort：
  F/libc: FORTIFY: pthread_mutex_destroy called on a destroyed mutex
  F/libc: Fatal signal 6 (SIGABRT) in tid 839 (OMX_ImgEnc)
把这两条 BL 指令改成 NOP（00 BF 00 BF）即可恢复 Android 8.1 的行为。
整个 167620 字节的文件只改 8 字节（两条 4 字节的 Thumb BL）。

用法：
  python3 patch_mmqjpeg.py stock.so patched.so
输入必须是原厂 md5 73d3594e71ed0866194ecaab845b781b 的文件；
其它版本会被拒绝，避免误伤相机 HAL。
"""
import hashlib
import sys
from pathlib import Path

STOCK_MD5 = "73d3594e71ed0866194ecaab845b781b"
PATCHED_MD5 = "d6911e58ee5a2b2146022041152066b6"
# 两条 BL 的 4 字节编码在原文件里各出现一次。
TARGETS = [
    bytes.fromhex("e8f71aec"),
    bytes.fromhex("e8f718ec"),
]
NOP = bytes.fromhex("00bf00bf")


def md5(data: bytes) -> str:
    return hashlib.md5(data).hexdigest()


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    data = bytearray(src.read_bytes())

    digest = md5(data)
    if digest == PATCHED_MD5:
        print("输入已经是补丁版，直接复制。")
        dst.write_bytes(data)
        return 0
    if digest != STOCK_MD5:
        print(f"拒绝：输入 md5 为 {digest}，期望 {STOCK_MD5}", file=sys.stderr)
        return 1

    for pat in TARGETS:
        first = data.find(pat)
        if first < 0:
            print(f"拒绝：找不到特征字节 {pat.hex()}", file=sys.stderr)
            return 1
        if data.find(pat, first + 1) >= 0:
            print(f"拒绝：特征字节 {pat.hex()} 不唯一", file=sys.stderr)
            return 1
        data[first:first + 4] = NOP
        print(f"patch @ 0x{first:x}: {pat.hex()} -> {NOP.hex()}")

    out = bytes(data)
    if md5(out) != PATCHED_MD5:
        print(f"警告：输出 md5 为 {md5(out)}，与记录的补丁版不一致", file=sys.stderr)
        return 1
    dst.write_bytes(out)
    print(f"完成：{dst}  md5={PATCHED_MD5}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
