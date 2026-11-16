#!/usr/bin/env bash
# build.sh — 统一编译入口（供 WorkBuddy / 人类一键调用）
#
# 为什么需要它：SSH 每次执行命令都是独立的非交互 shell，
# source 效果不跨命令保留，因此用一个入口封装"激活环境 + 切目录 + 编译"。
#
# 用法：
#   build.sh esp   [项目目录] [参数...]   → 激活 ESP 环境 + idf.py build
#   build.sh bk    [项目目录] [参数...]   → 激活 BK  环境 + make bk7258
#   build.sh stm32 [项目目录] [参数...]   → 激活 STM32环境 + pio run
#
# 示例：
#   ~/sdk/build.sh esp   ~/projects/esp/hello_world
#   ~/sdk/build.sh bk    ~/sdk/bk/bk_avdk/bk_idk PROJECT=my_proj
#   ~/sdk/build.sh stm32 ~/projects/stm32/myproj
#
set -euo pipefail

SDK_ROOT="${SDK_ROOT:-$HOME/sdk}"
TARGET="${1:-}"; shift 2>/dev/null || true

usage() { echo "用法: $0 {esp|bk|stm32} [项目目录] [编译参数...]" >&2; exit 1; }
[ -n "$TARGET" ] || usage

case "$TARGET" in
  esp)   ENV="$SDK_ROOT/esp-env.sh";;
  bk)    ENV="$SDK_ROOT/bk-env.sh";;
  stm32) ENV="$SDK_ROOT/stm32-env.sh";;
  *)     usage;;
esac

[ -f "$ENV" ] || { echo "未找到 $ENV，请先运行 setup.sh" >&2; exit 1; }
source "$ENV"

# 第一个参数若是存在的目录，则进入该目录
if [ $# -gt 0 ] && [ -d "$1" ]; then
  cd "$1"; shift 2>/dev/null || true
fi

case "$TARGET" in
  esp)   exec idf.py build "$@";;
  bk)    exec make bk7258 "$@";;
  stm32) exec pio run "$@";;
esac
