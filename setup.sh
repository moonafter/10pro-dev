#!/usr/bin/env bash
#
# setup.sh — 一加10Pro / DroidSpace Debian(aarch64) 固件开发环境一键配置
#
# 目标：在一部手机上同时搭建 ESP32(ESP-IDF)、BK7258(Armino)、STM32 三套交叉编译环境，
#       并且做到完全隔离、可重复执行（幂等）、可迁移复用。
#
# 隔离手段：
#   - 目录隔离：ESP 与 BK 的工具链、Python 环境、SDK 分别放在独立目录
#   - 环境变量隔离：不写入 .bashrc，只通过 source esp-env.sh / bk-env.sh 按需激活
#   - 工具链隔离：ESP 用 xtensa/riscv 工具链，BK 用 arm-none-eabi，互不混入全局 PATH
#
# 用法：
#   bash setup.sh                       # 默认安装到 $HOME/sdk
#   SDK_ROOT=/data/xxx bash setup.sh    # 自定义根目录
#   USE_CN_MIRROR=0 bash setup.sh       # 关闭国内镜像（海外网络）
#
set -euo pipefail

# ============================ 配置区（按需修改） ============================
SDK_ROOT="${SDK_ROOT:-$HOME/sdk}"                         # 所有环境的总根目录
USE_CN_MIRROR="${USE_CN_MIRROR:-1}"                       # 1=启用国内镜像加速
ESP_IDF_GIT_URL="${ESP_IDF_GIT_URL:-https://github.com/espressif/esp-idf.git}"
ESP_IDF_VERSION="${ESP_IDF_VERSION:-v5.5.1}"              # ESP-IDF 版本
ESP_TARGETS="${ESP_TARGETS:-esp32}"                       # 芯片目标，空格分隔，如 "esp32 esp32s3"
BK_AVDK_GIT_URL="${BK_AVDK_GIT_URL:-https://github.com/bekencorp/bk_avdk.git}"
BK_AVDK_BRANCH="${BK_AVDK_BRANCH:-release/v2.0.2}"        # Armino SDK 分支
ARM_TC_BASE="https://developer.arm.com/-/media/Files/downloads/gnu-rm/10.3-2021.10"
ARM_TC_FILE="gcc-arm-none-eabi-10.3-2021.10-aarch64-linux.tar.bz2"
ARM_TC_REV="rev=b748c39178c043b4915b04645d7774d8&hash=572217C8AFE83F1010753EA3E3A7EC2307DADD58"
STM32_INSTALL_PIO="${STM32_INSTALL_PIO:-1}"               # 1=安装 PlatformIO Core(pio run 一键编译)
# ============================================================================

ESP_ROOT="$SDK_ROOT/esp"
BK_ROOT="$SDK_ROOT/bk"
ESP_IDF="$ESP_ROOT/esp-idf"
ESP_TOOLS="$ESP_ROOT/tools"          # IDF_TOOLS_PATH
ESP_PYENV="$ESP_ROOT/python_env"     # IDF_PYTHON_ENV_PATH
BK_SDK="$BK_ROOT/bk_avdk"
BK_TOOLCHAIN="$BK_ROOT/toolchain"    # arm-none-eabi 工具链
BK_PYENV="$BK_ROOT/python_env"       # BK 专用 Python venv
STM32_ROOT="$SDK_ROOT/stm32"
STM32_TOOLCHAIN="$STM32_ROOT/toolchain"   # 软链复用 BK 的 arm-none-eabi
STM32_PYENV="$STM32_ROOT/python_env"      # STM32 专用 Python venv

log()  { printf '\033[1;32m[setup]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- 0. 架构与前置校验 ----------
check_arch() {
  log "检查系统架构..."
  [ "$(uname -m)" = "aarch64" ] || die "本脚本针对 aarch64(一加10Pro) 设计，当前架构: $(uname -m)"
}

# ---------- 1. 系统基础依赖 ----------
install_deps() {
  log "==> 安装系统基础依赖"
  export DEBIAN_FRONTEND=noninteractive
  apt update
  apt install -y \
    build-essential git curl wget ca-certificates \
    bzip2 unzip tar xz-utils \
    cmake ninja-build \
    python3 python3-pip python3-venv python-is-python3 \
    flex bison gperf ccache \
    libncurses-dev libffi-dev libssl-dev \
    libusb-1.0-0 pkg-config
  # BK SDK 要求 python 指向 python3
  if ! command -v python >/dev/null 2>&1; then
    ln -sf /usr/bin/python3 /usr/local/bin/python
  fi
}

# ---------- 2. ESP-IDF ----------
setup_esp() {
  log "==> 配置 ESP-IDF 环境（独立于 BK）"
  mkdir -p "$ESP_ROOT"
  mkdir -p "$ESP_PYENV"
  
  if [ ! -d "$ESP_IDF/.git" ]; then
    log "克隆 ESP-IDF $ESP_IDF_VERSION ..."
    git clone -b "$ESP_IDF_VERSION" "$ESP_IDF_GIT_URL" "$ESP_IDF"
  else
    log "ESP-IDF 已存在，跳过克隆"
  fi

  # 子模块（首次或缺失时补齐）
  if [ ! -d "$ESP_IDF/components/esp_wifi/.git" ] && [ ! -f "$ESP_IDF/components/esp_wifi/.git" ]; then
    log "拉取 ESP-IDF 子模块 ..."
    git -C "$ESP_IDF" submodule update --init --recursive \
      || warn "子模块拉取失败，稍后可进入 $ESP_IDF 重试: git submodule update --init --recursive"
  fi

  # 国内镜像 + 独立工具/Python 路径（实现与 BK 的完全隔离）
  if [ "$USE_CN_MIRROR" = "1" ]; then
    export IDF_GITHUB_ASSETS="dl.espressif.cn/github_assets"
    export PIP_INDEX_URL="https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple"
  fi
  export IDF_TOOLS_PATH="$ESP_TOOLS"
  export IDF_PYTHON_ENV_PATH="$ESP_PYENV"

  log "安装 ESP-IDF 工具链（目标: $ESP_TARGETS）..."
  ( cd "$ESP_IDF" && ./install.sh $ESP_TARGETS )

  log "ESP-IDF 完成。激活: source $SDK_ROOT/esp-env.sh"
}

# ---------- 3. BK7258 (Armino) ----------
setup_bk() {
  log "==> 配置 BK7258(Armino) 环境（独立于 ESP）"
  mkdir -p "$BK_ROOT"

  # 3.1 arm-none-eabi 工具链
  if [ ! -x "$BK_TOOLCHAIN/bin/arm-none-eabi-gcc" ]; then
    log "下载 arm-none-eabi 工具链(aarch64)..."
    local tmp="/tmp/$ARM_TC_FILE"
    if curl -fL --retry 3 -o "$tmp" "$ARM_TC_BASE/$ARM_TC_FILE?$ARM_TC_REV"; then
      mkdir -p "$BK_TOOLCHAIN"
      tar -xjf "$tmp" --strip-components=1 -C "$BK_TOOLCHAIN"
      rm -f "$tmp"
    else
      warn "自动下载失败（ARM 官网可能要求登录）。"
      warn "请手动从 https://developer.arm.com/downloads/-/gnu-rm 下载"
      warn "  $ARM_TC_FILE 放到 /tmp/ 后重跑本脚本。"
    fi
  else
    log "arm-none-eabi 工具链已存在，跳过"
  fi

  # 3.2 Armino SDK
  if [ ! -d "$BK_SDK/.git" ]; then
    log "克隆 Armino SDK ($BK_AVDK_BRANCH) ..."
    if ! git clone -b "$BK_AVDK_BRANCH" --recurse-submodules "$BK_AVDK_GIT_URL" "$BK_SDK"; then
      warn "递归克隆失败，改为基础克隆 + 手动补子模块"
      git clone -b "$BK_AVDK_BRANCH" "$BK_AVDK_GIT_URL" "$BK_SDK"
      git -C "$BK_SDK" submodule update --init --recursive \
        || warn "子模块仍失败，稍后手动: git -C $BK_SDK submodule update --init --recursive"
    fi
  else
    log "Armino SDK 已存在，跳过克隆"
  fi

  # 3.3 修正 defconfig 里的工具链路径
  local def="$BK_SDK/middleware/soc/bk7258/bk7258.defconfig"
  if [ -f "$def" ] && [ -x "$BK_TOOLCHAIN/bin/arm-none-eabi-gcc" ]; then
    sed -i "s#^CONFIG_TOOLCHAIN_PATH=.*#CONFIG_TOOLCHAIN_PATH=\"$BK_TOOLCHAIN/bin\"#" "$def"
    log "已写入工具链路径: $def"
  elif [ -f "$def" ]; then
    warn "工具链未就绪，暂未修改 defconfig（$def）"
  fi

  # 3.4 独立 Python venv（与 ESP 完全隔离）
  if [ ! -x "$BK_PYENV/bin/python" ]; then
    log "创建 BK 专用 Python venv ..."
    python3 -m venv "$BK_PYENV"
    local pip="$BK_PYENV/bin/pip"
    if [ "$USE_CN_MIRROR" = "1" ]; then
      "$pip" install -q -i https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple -U pip
      "$pip" install -q -i https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple \
        pycryptodome click future click_option_group cryptography jinja2 PyYAML cbor2 intelhex
    else
      "$pip" install -q pycryptodome click future click_option_group cryptography jinja2 PyYAML cbor2 intelhex
    fi
  else
    log "BK Python venv 已存在，跳过"
  fi

  log "BK 完成。激活: source $SDK_ROOT/bk-env.sh"
}

# ---------- 3.5 STM32 ----------
setup_stm32() {
  log "==> 配置 STM32 环境（独立于 ESP/BK）"
  mkdir -p "$STM32_ROOT"

  # 1) arm-none-eabi 工具链：STM32 与 BK 是同一套 ARM GCC，
  #    优先软链复用 BK 那份以省约 500MB；BK 缺失时则独立下载。
  if [ ! -x "$STM32_TOOLCHAIN/bin/arm-none-eabi-gcc" ]; then
    if [ -x "$BK_ROOT/toolchain/bin/arm-none-eabi-gcc" ]; then
      log "复用 BK 已装的 arm-none-eabi 工具链（软链）"
      ln -s "$BK_ROOT/toolchain" "$STM32_TOOLCHAIN"
    else
      log "下载 arm-none-eabi 工具链(aarch64)..."
      local tmp="/tmp/$ARM_TC_FILE"
      if curl -fL --retry 3 -o "$tmp" "$ARM_TC_BASE/$ARM_TC_FILE?$ARM_TC_REV"; then
        mkdir -p "$STM32_TOOLCHAIN"
        tar -xjf "$tmp" --strip-components=1 -C "$STM32_TOOLCHAIN"
        rm -f "$tmp"
      else
        warn "arm-none-eabi 下载失败，请手动下载 $ARM_TC_FILE 放到 /tmp/ 后重跑本脚本。"
      fi
    fi
  else
    log "STM32 工具链已就绪，跳过"
  fi

  # 2) 独立 Python venv（与 ESP/BK 隔离）
  if [ ! -x "$STM32_PYENV/bin/python" ]; then
    log "创建 STM32 专用 Python venv ..."
    python3 -m venv "$STM32_PYENV"
  fi

  # 3) 可选：PlatformIO Core（一键编译 STM32，framework/工具链按需自动下载）
  if [ "$STM32_INSTALL_PIO" = "1" ]; then
    if [ ! -x "$STM32_PYENV/bin/pio" ]; then
      log "安装 PlatformIO Core ..."
      local pip="$STM32_PYENV/bin/pip"
      if [ "$USE_CN_MIRROR" = "1" ]; then
        "$pip" install -q -i https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple -U pip
        "$pip" install -q -i https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple platformio
      else
        "$pip" install -q platformio
      fi
    else
      log "PlatformIO 已安装，跳过"
    fi
  fi

  log "STM32 完成。激活: source $SDK_ROOT/stm32-env.sh"
}

# ---------- 4. 生成环境激活脚本 ----------
write_env_scripts() {
  log "==> 生成环境激活脚本"

  cat > "$SDK_ROOT/esp-env.sh" <<'EOF'
#!/usr/bin/env bash
# ESP-IDF 环境激活：进入 ESP 项目目录后执行  source $HOME/sdk/esp-env.sh
SDK_ROOT="${SDK_ROOT:-$HOME/sdk}"
export IDF_PATH="$SDK_ROOT/esp/esp-idf"
export IDF_TOOLS_PATH="$SDK_ROOT/esp/tools"
export IDF_PYTHON_ENV_PATH="$SDK_ROOT/esp/python_env"
if [ ! -f "$IDF_PATH/export.sh" ]; then
  echo "[esp-env] 未找到 ESP-IDF，请先运行 setup.sh" >&2
  return 1 2>/dev/null || exit 1
fi
source "$IDF_PATH/export.sh" "$@"
EOF

  cat > "$SDK_ROOT/bk-env.sh" <<'EOF'
#!/usr/bin/env bash
# BK Armino 环境激活：进入 bk_idk 目录后执行  source $HOME/sdk/bk-env.sh
SDK_ROOT="${SDK_ROOT:-$HOME/sdk}"
BK_ROOT="$SDK_ROOT/bk"
export PATH="$BK_ROOT/toolchain/bin:$PATH"
export CONFIG_TOOLCHAIN_PATH="$BK_ROOT/toolchain/bin"
if [ -f "$BK_ROOT/python_env/bin/activate" ]; then
  source "$BK_ROOT/python_env/bin/activate"
fi
echo "[bk-env] $(arm-none-eabi-gcc --version 2>/dev/null | head -1)"
echo "[bk-env] SDK: $BK_ROOT/bk_avdk/bk_idk"
EOF

  cat > "$SDK_ROOT/stm32-env.sh" <<'EOF'
#!/usr/bin/env bash
# STM32 环境激活：进入 STM32 工程目录后执行  source $HOME/sdk/stm32-env.sh
SDK_ROOT="${SDK_ROOT:-$HOME/sdk}"
STM32_ROOT="$SDK_ROOT/stm32"
export PATH="$STM32_ROOT/toolchain/bin:$PATH"
if [ -f "$STM32_ROOT/python_env/bin/activate" ]; then
  source "$STM32_ROOT/python_env/bin/activate"
fi
echo "[stm32-env] $(arm-none-eabi-gcc --version 2>/dev/null | head -1)"
command -v pio >/dev/null 2>&1 && echo "[stm32-env] PlatformIO: $(pio --version 2>/dev/null)"
echo "[stm32-env] 裸编译: arm-none-eabi-gcc | 一键编译: pio run"
EOF

  cat > "$SDK_ROOT/build.sh" <<'EOF'
#!/usr/bin/env bash
# 统一编译入口（供 WorkBuddy / 人类一键调用）
# 用法: build.sh {esp|bk|stm32} [项目目录] [编译参数...]
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
if [ $# -gt 0 ] && [ -d "$1" ]; then
  cd "$1"; shift 2>/dev/null || true
fi
case "$TARGET" in
  esp)   exec idf.py build "$@";;
  bk)    exec make bk7258 "$@";;
  stm32) exec pio run "$@";;
esac
EOF

  cat > "$SDK_ROOT/check_env.sh" <<'EOF'
#!/usr/bin/env bash
# check_env.sh — 根据目标芯片型号判断编译环境是否就绪
# 用法: check_env.sh esp32 | esp32s3 | esp32c3 | bk7258 | stm32
# 退出码: 0=就绪 1=未就绪 2=未知芯片
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
EOF

  chmod +x "$SDK_ROOT/esp-env.sh" "$SDK_ROOT/bk-env.sh" "$SDK_ROOT/stm32-env.sh" "$SDK_ROOT/build.sh" "$SDK_ROOT/check_env.sh"

  # 若脚本同目录带有 WORKBUDDY.md，则复制到 SDK_ROOT 供 WorkBuddy 阅读
  local src_workbuddy
  src_workbuddy="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/WORKBUDDY.md"
  if [ -f "$src_workbuddy" ]; then
    cp "$src_workbuddy" "$SDK_ROOT/WORKBUDDY.md"
    log "已放置 AI 规则说明: $SDK_ROOT/WORKBUDDY.md"
  fi
}

# ---------- 主流程 ----------
main() {
  log "SDK 根目录: $SDK_ROOT"
  mkdir -p "$SDK_ROOT"
  check_arch
  install_deps
  setup_esp
  setup_bk
  setup_stm32
  write_env_scripts
  echo
  log "全部完成 ✔"
  echo "  ESP  环境: source $SDK_ROOT/esp-env.sh"
  echo "  BK   环境: source $SDK_ROOT/bk-env.sh"
  echo "  STM32环境: source $SDK_ROOT/stm32-env.sh"
  echo "  统一编译: $SDK_ROOT/build.sh {esp|bk|stm32} [项目目录]"
  echo "  给 AI 的规则: 把 $SDK_ROOT/WORKBUDDY.md 内容告知 WorkBuddy"
  echo "  目录结构与排障见 README.md"
}

main "$@"
