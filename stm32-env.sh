#!/usr/bin/env bash
# STM32 环境激活（独立模板，可单独 scp 到手机使用）
# 用法：进入 STM32 工程目录后执行  source stm32-env.sh
SDK_ROOT="${SDK_ROOT:-$HOME/sdk}"
STM32_ROOT="$SDK_ROOT/stm32"
export PATH="$STM32_ROOT/toolchain/bin:$PATH"
if [ -f "$STM32_ROOT/python_env/bin/activate" ]; then
  source "$STM32_ROOT/python_env/bin/activate"
fi
echo "[stm32-env] $(arm-none-eabi-gcc --version 2>/dev/null | head -1)"
command -v pio >/dev/null 2>&1 && echo "[stm32-env] PlatformIO: $(pio --version 2>/dev/null)"
echo "[stm32-env] 裸编译: arm-none-eabi-gcc | 一键编译: pio run"
