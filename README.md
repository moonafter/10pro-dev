# 手机端固件开发环境（一加10Pro / DroidSpace Debian aarch64）

在手机上搭建 **ESP32（ESP-IDF）**、**BK7258（Armino）**、**STM32** 三套交叉编译环境，做到**完全隔离、可复用、可迁移**。环境变量不写入 `.bashrc`，进入哪个项目就 `source` 哪个环境，各套工具链和 Python 依赖互不污染。

## 目录结构

```
~/sdk/                       # SDK_ROOT，可自定义
├── setup.sh                 # 一键配置脚本（幂等，可重复运行）
├── esp-env.sh               # 激活 ESP 环境（由 setup.sh 生成）
├── bk-env.sh                # 激活 BK  环境（由 setup.sh 生成）
├── stm32-env.sh             # 激活 STM32 环境（由 setup.sh 生成）
├── build.sh                 # 统一编译入口（由 setup.sh 生成）
├── check_env.sh             # 按芯片型号自检环境（由 setup.sh 生成）
├── WORKBUDDY.md             # 给 WorkBuddy 的编译规则说明（由 setup.sh 复制）
├── esp/                     # ─── ESP 环境（独立）───
│   ├── esp-idf/             #   ESP-IDF 源码
│   ├── tools/               #   IDF_TOOLS_PATH：xtensa/riscv 工具链、cmake、ninja…
│   └── python_env/          #   IDF_PYTHON_ENV_PATH：ESP 专用 Python venv
├── bk/                      # ─── BK 环境（独立）───
│   ├── bk_avdk/             #   Armino SDK 源码
│   ├── toolchain/           #   arm-none-eabi 交叉工具链
│   └── python_env/          #   BK 专用 Python venv
└── stm32/                   # ─── STM32 环境（独立）───
    ├── toolchain/           #   arm-none-eabi 工具链（软链复用 BK 那份）
    └── python_env/          #   STM32 专用 Python venv（含 PlatformIO）
```

> 三套环境唯一共享的是 `/usr` 下的系统包（git、cmake、ninja、build-essential 等），**工具链、Python 依赖、环境变量全部隔离**。STM32 与 BK 是同一套 `arm-none-eabi` 工具链，STM32 通过软链复用 BK 那份（纯通用、无状态，复用不破坏隔离，省约 500MB）。

## 快速开始

1. 把整个 `phone-dev-env` 目录传到手机容器：

```bash
scp -P 22 -r phone-dev-env root@192.168.1.100:/root/
```

2. 进容器终端，运行（约 15~20 GB 磁盘，务必先确认空间）：

```bash
cd /root/phone-dev-env
bash setup.sh
```

3. 日常使用（三套环境互不干扰）：

```bash
# —— ESP 项目 ——
cd ~/projects/esp/hello_world
source ~/sdk/esp-env.sh          # 激活 ESP 环境
idf.py build

# —— BK 项目 ——
cd ~/sdk/bk/bk_avdk/bk_idk
source ~/sdk/bk-env.sh           # 激活 BK 环境
make bk7258 PROJECT=media/doorbell

# —— STM32 项目 ——
source ~/sdk/stm32-env.sh        # 激活 STM32 环境
# 方式一：PlatformIO 一键编译
pio run
# 方式二：裸工具链编译（STM32CubeMX 生成的 Makefile/CMake 工程）
make -j4                        # 或 cmake --build build
```

## 让 WorkBuddy 编译（统一入口）

WorkBuddy 通过 SSH 执行命令时，**每次都是独立的非交互 shell**，`source` 的效果不会跨命令保留。因此给它一个统一入口 `~/sdk/build.sh`，它只需记一条命令即可正确编译：

```bash
~/sdk/build.sh esp   ~/projects/esp/hello_world
~/sdk/build.sh bk    ~/sdk/bk/bk_avdk/bk_idk PROJECT=my_proj
~/sdk/build.sh stm32 ~/projects/stm32/myproj
```

`build.sh` 内部会**自动 `source` 正确环境 → 切到项目目录 → 执行编译**，AI 无需理解三套环境的隔离细节。

**让 WorkBuddy 知道规则**（任选其一）：

1. 把 `WORKBUDDY.md` 内容直接贴进任务（或在任务里说"按 `~/sdk/WORKBUDDY.md` 的规则编译"）；
2. 将规则存入 WorkBuddy 的记忆/知识库，长期生效；
3. 简单任务直接在对话里说一句："编译 ESP 项目 `~/projects/esp/hello_world`，用 `~/sdk/build.sh esp`"。

## 电脑端连接 WorkBuddy（SSH MCP）

WorkBuddy 本身不内置 SSH 客户端，通过 **SSH MCP**（`@fangjunjie/ssh-mcp-server`）桥接。前提：手机侧 SSH 已装好、DroidSpace 端口转发 `22:22`、电脑能 `ssh root@手机IP` 免密登录（建议已配密钥）。

### 1. 电脑端 mcp.json（密钥登录版）

写入电脑端 `~/.workbuddy/mcp.json`（Windows：`C:\Users\你的用户名\.workbuddy\mcp.json`，macOS/Linux：`~/.workbuddy/mcp.json`），并与已有其他 MCP 配置**合并**：

```json
{
  "mcpServers": {
    "ssh-server": {
      "command": "npx",
      "args": ["-y", "@fangjunjie/ssh-mcp-server",
               "--host", "192.168.1.100",
               "--port", "22",
               "--username", "root",
               "--privateKey", "C:/Users/你的用户名/.ssh/workbuddy_ed25519"],
      "disabled": false
    }
  }
}
```

- `192.168.1.100` 换成手机实际局域网 IP；
- `--privateKey` 是电脑端私钥的**绝对路径**（Windows 用 `C:/...`，macOS/Linux 用 `/Users/...` 或 `/home/...`）；
- 参数名是 `--privateKey`（不是 `--privateKeyPath`），私钥权限需 `chmod 600`；
- 密钥生成与放手机：`ssh-keygen -t ed25519 -f ~/.ssh/workbuddy_ed25519`，再用 `ssh-copy-id -i ~/.ssh/workbuddy_ed25519.pub root@手机IP` 把公钥放上手机。

### 2. 保存后点「信任」

配置保存后**不会自动生效**，需在 WorkBuddy「插件 → MCP 服务器」里对 `ssh-server` 点「信任」，状态灯**绿色**即连上。红色则排查：手机 SSH 是否在跑 → 电脑能否免密登入 → JSON 路径/格式。

### 3. 提示词模板

连接由 `mcp.json` + 信任完成，提示词只负责**指挥它干活 + 告诉环境规则**。可直接复制：

**标准编译（推荐）**：

```
通过 SSH 在手机上编译固件。环境规则见 ~/sdk/WORKBUDDY.md，先读它，再严格按 build.sh 方式编译。
任务：编译 ESP 项目 ~/projects/esp/hello_world（芯片 esp32）。
先跑 ~/sdk/check_env.sh esp32 自检，就绪再编译；完成后报告 build/ 下 .bin 产物路径和大小。
烧录放电脑，不要在手机上烧录。
```

**首次验证连接**：

```
通过 SSH 连到手机开发服务器，先执行 whoami && uname -m && df -h /，确认能连上、架构是 aarch64、磁盘够用，把结果报告给我。
```

**长期复用**：把 `WORKBUDDY.md` 的规则存进 WorkBuddy 记忆后，提示词可简化为一句："按既定规则编译 ~/projects/esp/hello_world"。

## 按芯片型号自检环境

不同芯片对应不同交叉工具链，可用 `check_env.sh` 快速判断某芯片的环境是否搭建好：

```bash
~/sdk/check_env.sh esp32     # ESP32/S2/S3 → xtensa-esp-elf
~/sdk/check_env.sh esp32c3   # ESP32-C2/C3/C6/H2/P4 → riscv32-esp-elf
~/sdk/check_env.sh bk7258    # BK72xx → arm-none-eabi
~/sdk/check_env.sh stm32     # STM32 → arm-none-eabi（复用 BK）
```

输出 `[OK]` 表示就绪（退出码 0），`[NG]` 表示未就绪（退出码 1），并提示如何补装。WorkBuddy 编译前也可用它先自检，避免盲目编译报错。

## 配置变量（setup.sh 顶部）

| 变量 | 默认值 | 说明 |
|---|---|---|
| `SDK_ROOT` | `$HOME/sdk` | 环境总根目录，可用环境变量覆盖 |
| `USE_CN_MIRROR` | `1` | 1=启用国内镜像（PyPI 清华源 + ESP 工具乐鑫源） |
| `ESP_IDF_VERSION` | `v5.5.1` | ESP-IDF 版本 |
| `ESP_TARGETS` | `esp32` | 芯片目标，可改 `esp32 esp32s3 esp32c3` |
| `BK_AVDK_BRANCH` | `release/v2.0.2` | Armino SDK 分支 |
| `STM32_INSTALL_PIO` | `1` | 1=安装 PlatformIO Core，0=只用裸 arm-none-eabi |

## 隔离机制说明

| 层面 | ESP | BK | STM32 |
|---|---|---|---|
| 工具链 | `esp/tools`（xtensa-esp-elf / riscv32-esp-elf） | `bk/toolchain`（arm-none-eabi） | `stm32/toolchain`（软链复用 BK 的 arm-none-eabi） |
| Python | `esp/python_env`（IDF 官方 venv） | `bk/python_env`（自建 venv） | `stm32/python_env`（自建 venv，含 PlatformIO） |
| 环境变量 | `IDF_PATH` / `IDF_TOOLS_PATH` / `IDF_PYTHON_ENV_PATH` | `PATH` 前缀 + `CONFIG_TOOLCHAIN_PATH` | `PATH` 前缀 |
| 激活方式 | `source esp-env.sh` | `source bk-env.sh` | `source stm32-env.sh` |

因为工具链可执行文件名不同（`xtensa-esp32-elf-gcc` vs `arm-none-eabi-gcc`），即使误把两个环境同时激活也不会发生命令冲突；真正的隔离点在于 `IDF_TOOLS_PATH` 与 `CONFIG_TOOLCHAIN_PATH` 各自指向独立目录。

## 常见问题

**1. arm-none-eabi 工具链自动下载失败**
ARM 官网部分下载需登录，脚本失败时会提示。手动从 <https://developer.arm.com/downloads/-/gnu-rm> 下载 `gcc-arm-none-eabi-10.3-2021.10-aarch64-linux.tar.bz2` 放到容器 `/tmp/`，重跑 `setup.sh` 即可（脚本会自动解压）。

**2. 国内 git clone 慢 / 子模块超时**
- ESP-IDF：把 `ESP_IDF_GIT_URL` 改为 gitee 镜像 `https://gitee.com/EspressifSystems/esp-idf.git`；工具链下载已默认走乐鑫国内源。
- Armino：可先 `git clone` 主仓库，再单独 `git submodule update --init --recursive`，脚本已内置此降级逻辑。

**3. 磁盘空间不足**
ESP-IDF 工具链 + SDK 约需 14 GB，BK 工具链 + SDK 约 3~5 GB。建议容器用 ext4 sparse image，并预留 64 GB 以上剩余空间。`df -h` 随时查看。

**4. 改了 SDK_ROOT 后 env 脚本不生效**
`esp-env.sh` / `bk-env.sh` 默认读 `$SDK_ROOT`（缺省 `$HOME/sdk`）。source 前先 `export SDK_ROOT=/你的路径`，或直接改脚本第一行。

**5. 编译产物在哪（供烧录）**
- ESP：`build/bootloader/bootloader.bin`、`build/partition_table/partition-table.bin`、`build/项目名.bin`
- BK：`build/app/bk7258/all-app.bin`（完整镜像）
- STM32：PlatformIO 在 `.pio/build/<board>/firmware.bin`；裸编译在 `build/` 下的 `.elf`/`.bin`/`.hex`

烧录放电脑：ESP 用 `esptool.py`，BK 用博通官方烧录工具，STM32 用 ST-Link（STM32CubeProgrammer / STM32 ST-LINK Utility / `st-flash`）；固件用 `scp` 拉回电脑即可（详见前面对话的工作流）。

**6. STM32 工具链为何复用 BK 的 arm-none-eabi**
STM32 与 BK7258 都是 Cortex-M 芯片，交叉编译器同为 `arm-none-eabi`（纯只读、无状态），共享不会互相污染，反而省约 500MB。`stm32/toolchain` 是指向 `bk/toolchain` 的软链；若 BK 工具链缺失，脚本会自动为 STM32 单独下载一份。两边的隔离靠的是**独立的 venv 和激活脚本**，而不是重复的工具链。

**7. PlatformIO 的 aarch64 支持**
PlatformIO Core 官方支持 Linux ARM64。个别 framework/toolchain 若缺 arm64 预编译包，`pio run` 会报错，此时改用方式二（`STM32CubeMX` 生成 Makefile/CMake 工程 + 裸 `arm-none-eabi-gcc` 编译）即可，两条路线共享同一份工具链。
