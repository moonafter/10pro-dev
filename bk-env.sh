#!/usr/bin/env bash
# BK Armino 环境激活（独立模板，可单独 scp 到手机使用）
# 用法：进入 bk_avdk/bk_idk 目录后执行  source bk-env.sh
SDK_ROOT="${SDK_ROOT:-$HOME/sdk}"
BK_ROOT="$SDK_ROOT/bk"
export PATH="$BK_ROOT/toolchain/bin:$PATH"
export CONFIG_TOOLCHAIN_PATH="$BK_ROOT/toolchain/bin"
if [ -f "$BK_ROOT/python_env/bin/activate" ]; then
  source "$BK_ROOT/python_env/bin/activate"
fi
echo "[bk-env] $(arm-none-eabi-gcc --version 2>/dev/null | head -1)"
echo "[bk-env] SDK: $BK_ROOT/bk_avdk/bk_idk"
