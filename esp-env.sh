#!/usr/bin/env bash
# ESP-IDF 环境激活（独立模板，可单独 scp 到手机使用）
# 用法：进入 ESP 项目目录后执行  source esp-env.sh [额外参数透传给 export.sh]
SDK_ROOT="${SDK_ROOT:-$HOME/sdk}"
export IDF_PATH="$SDK_ROOT/esp/esp-idf"
export IDF_TOOLS_PATH="$SDK_ROOT/esp/tools"
export IDF_PYTHON_ENV_PATH="$SDK_ROOT/esp/python_env"
if [ ! -f "$IDF_PATH/export.sh" ]; then
  echo "[esp-env] 未找到 ESP-IDF，请先运行 setup.sh" >&2
  return 1 2>/dev/null || exit 1
fi
source "$IDF_PATH/export.sh" "$@"
