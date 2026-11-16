#!/usr/bin/env bash
# check_env.sh — 根据目标芯片型号判断编译环境是否就绪
#
# 原理：不同芯片对应不同交叉工具链，检查对应工具链是否存在即可判断环境是否搭建好。
#   ESP32/S2/S3        → xtensa-esp-elf
#   ESP32-C2/C3/C6/H2/P4 → riscv32-esp-elf
#   BK72xx            → arm-none-eabi
#   STM32             → arm-none-eabi（复用 BK 工具链）
#
# 用法：
#   check_env.sh esp32        # 判断 ESP32(Xtensa) 工具链
#   check_env.sh esp32s3
#   check_env.sh esp32c3      # RISC-V
#   check_env.sh bk7258
#   check_env.sh stm32
#
# 退出码：0=就绪，1=未就绪，2=未知芯片
set -uo pipefail

SDK_ROOT="${SDK_ROOT:-$HOME/sdk}"
ESP_TOOLS="$SDK_ROOT/esp/tools"
BK_TC="$SDK_ROOT/bk/toolchain/bin"
STM32_TC="$SDK_ROOT/stm32/toolchain/bin"

CHIP="${1:-}"
if [ -z "$CHIP" ]; then
  echo "用法: $0 <芯片型号>  例: esp32 / esp32s3 / esp32c3 / bk7258 / stm32" >&2
  exit 2
fi

have() { ls "$1" >/dev/null 2>&1; }

case "${CHIP,,}" in
  esp32|esp32s2|esp32s3)
    if have "$ESP_TOOLS/tools/xtensa-esp-elf/"*/xtensa-esp-elf/bin/xtensa-esp-elf-gcc; then
      echo "[OK] $CHIP 就绪（xtensa-esp-elf 工具链已安装）"
    else
      echo "[NG] $CHIP 未就绪：缺 xtensa-esp-elf 工具链；请在 setup.sh 的 ESP_TARGETS 加入 $CHIP 后重跑" >&2
      exit 1
    fi
    ;;
  esp32c2|esp32c3|esp32c6|esp32h2|esp32p4)
    if have "$ESP_TOOLS/tools/riscv32-esp-elf/"*/riscv32-esp-elf/bin/riscv32-esp-elf-gcc; then
      echo "[OK] $CHIP 就绪（riscv32-esp-elf 工具链已安装）"
    else
      echo "[NG] $CHIP 未就绪：缺 riscv32-esp-elf 工具链；请在 setup.sh 的 ESP_TARGETS 加入 $CHIP 后重跑" >&2
      exit 1
    fi
    ;;
  bk*)
    if [ -x "$BK_TC/arm-none-eabi-gcc" ]; then
      echo "[OK] $CHIP 就绪（arm-none-eabi 工具链已安装）"
    else
      echo "[NG] $CHIP 未就绪：缺 arm-none-eabi 工具链；重跑 setup.sh 补装" >&2
      exit 1
    fi
    ;;
  stm32*)
    if [ -x "$STM32_TC/arm-none-eabi-gcc" ]; then
      echo "[OK] $CHIP 就绪（arm-none-eabi 工具链已安装）"
    else
      echo "[NG] $CHIP 未就绪：缺 arm-none-eabi 工具链（STM32 复用 BK 工具链，请先确保 BK 已装）" >&2
      exit 1
    fi
    ;;
  *)
    echo "[?] 未知芯片: $CHIP" >&2
    echo "    支持: esp32 esp32s2 esp32s3 esp32c2 esp32c3 esp32c6 esp32h2 esp32p4 bk* stm32*" >&2
    exit 2
    ;;
esac
