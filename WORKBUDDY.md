# 手机固件编译环境说明（供 WorkBuddy / AI 阅读）

这是一部通过 SSH 连接的手机（DroidSpace Debian aarch64），上面有三套**隔离**的交叉编译环境。编译固件请严格遵守下面的规则。

## 唯一编译入口：`~/sdk/build.sh`

用法：`~/sdk/build.sh <目标> [项目目录] [参数...]`

| 目标 | 实际执行的命令 | 示例 |
|---|---|---|
| `esp` | `idf.py build` | `~/sdk/build.sh esp ~/projects/esp/hello_world` |
| `bk` | `make bk7258` | `~/sdk/build.sh bk ~/sdk/bk/bk_avdk/bk_idk PROJECT=my_proj` |
| `stm32` | `pio run` | `~/sdk/build.sh stm32 ~/projects/stm32/myproj` |

## 项目目录约定

所有项目代码统一放在 `~/projects/<平台>/<项目>` 下，**严禁放进 `~/sdk`**（`~/sdk` 是环境区，重装会整个删除，放进去会丢代码）。

| 平台 | 项目位置 | 说明 |
|---|---|---|
| ESP | `~/projects/esp/<项目>` | 自由目录，`source` 环境后即可编译 |
| STM32 | `~/projects/stm32/<项目>` | 自由目录（PlatformIO 或 STM32CubeMX 工程） |
| BK | `~/projects/bk/<项目>` | 代码放这里，再软链进 SDK（见下） |

**BK 特殊处理**：Armino 的 `make bk7258 PROJECT=xxx` 只能编译 `bk_idk/projects/` 下的工程，所以 BK 代码放独立目录后，用软链挂进 SDK：

```bash
ln -s ~/projects/bk/my_proj ~/sdk/bk/bk_avdk/bk_idk/projects/my_proj
```

规则：
- 找不到项目时，优先去 `~/projects/` 下按平台子目录查找。
- BK 工程的编译目录固定是 `~/sdk/bk/bk_avdk/bk_idk`，`PROJECT=<项目名>` 是相对 `projects/` 的路径。

## 必须遵守的规则

1. **编译前必须加载对应环境**，不要裸跑 `make` / `idf.py` / `pio`。
2. **优先使用 `~/sdk/build.sh`**，它已自动 `source` 正确环境并切到项目目录。
3. **不要同时加载两套环境**（三套环境的工具链和 Python 依赖相互隔离，混用会出错）。
4. **编译前可先自检环境**：`~/sdk/check_env.sh <芯片型号>`，输出 `[OK]` 表示就绪、`[NG]` 表示未就绪（退出码 0/1）。未就绪时按提示补装，不要盲目编译。
5. 若需执行编译之外的命令（如 `git`、查看代码），可单独 `source` 对应环境后再执行：
   - ESP：`source ~/sdk/esp-env.sh && idf.py build`
   - BK：`source ~/sdk/bk-env.sh && make bk7258 PROJECT=xxx`
   - STM32：`source ~/sdk/stm32-env.sh && pio run`
6. **项目代码放 `~/projects/<平台>/<项目>`**，严禁放进 `~/sdk`；BK 工程需先软链进 `bk_idk/projects/`（详见「项目目录约定」）。

## 编译产物位置

| 目标 | 产物 |
|---|---|
| ESP | `build/bootloader/bootloader.bin`、`build/partition_table/partition-table.bin`、`build/<项目名>.bin` |
| BK | `build/app/bk7258/all-app.bin`（完整镜像） |
| STM32 | `.pio/build/<board>/firmware.bin`（PlatformIO）或 `build/*.bin`（裸编译） |

## 其他约定

- 烧录**不在手机上进行**，请只负责编译，把 `.bin` 用 `scp` 交给电脑端烧录。
- 三套环境的激活脚本：`~/sdk/esp-env.sh`、`~/sdk/bk-env.sh`、`~/sdk/stm32-env.sh`。
- 环境自检：`~/sdk/check_env.sh esp32`（或 `esp32s3`/`esp32c3`/`bk7258`/`stm32`），按芯片型号判断工具链是否就绪。
- 环境搭建脚本：`~/phone-dev-env/setup.sh`（或 `~/sdk/setup.sh`），仅首次配置时运行。

## 附：电脑端接入配置与提示词模板

本机通过 **SSH MCP**（`@fangjunjie/ssh-mcp-server`）接入 WorkBuddy。以下为电脑端 `mcp.json` 配置（密钥登录版，路径为 Windows 示例，放到电脑端 `~/.workbuddy/mcp.json`，保存后在 WorkBuddy「插件 → MCP 服务器」里点「信任」）：

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

- `192.168.1.100` 换成手机实际局域网 IP；macOS/Linux 的私钥路径用 `/Users/...` 或 `/home/...`。
- 参数名是 `--privateKey`（不是 `--privateKeyPath`），私钥权限需 `chmod 600`。

### 提示词模板（可直接复制）

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
