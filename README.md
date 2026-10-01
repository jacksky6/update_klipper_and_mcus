> [!CAUTION]
> ## RP2040 用户请注意
> https://github.com/Klipper3d/klipper/pull/6725 引入 RP2350 后，UKAM 保存的配置文件可能会损坏。这是因为 RP2350 的实现改变了配置数据的处理方式，因而与已有配置文件不兼容。
>
> 为避免出现问题，下次请使用 `menuconfig` 选项运行 UKAM：
> ```
> ./ukam.sh -m
> ```
> 这样可以检查并调整 MCU 配置，例如选择正确的开发板型号或通信接口。

![UKAM_Banner](./images/banner.png)
# **UKAM[^1] v0.0.9**（无限空闲）

[^1]: 使用本机 Klipper 或 Kalico 源码，一次性更新全部 MCU 固件。

UKAM 是一个用于批量更新 MCU 固件（主板、RPi、CAN、Pico 等）的 Bash 脚本，并会**保留配置文件，供下次更新使用**。它不会更新或回滚 Klipper/Kalico 主机端代码。

> [!WARNING]
> ### 使用须知
> 现代 MCU 的写入次数有限（EEPROM 超过 10 万次，STM32 芯片约 1 万次）。每次发布都更新固件，可能缩短 MCU 的使用寿命。
>
> ### 多久使用一次 UKAM？
> UKAM 会检查固件版本；若固件已经是最新版本，则会跳过刷写。
>
> 通常没有必要让 MCU 固件版本始终与主机端版本一致。Klipper 的主要变动来自主机代码和文档。
>
> 建议的工作方式是：_“检查是否有会影响打印机的 C 文件改动”_，或者等 Klipper 在启动时提示需要更新 MCU 固件。
>
> ### 为什么还需要 UKAM？
> 当 Klipper 要求更新 MCU 时，它能让这个过程更轻松。

## 目录

- [UKAM 的功能](#ukam-的功能)
- [安装](#安装)
- [通过 Moonraker 更新 UKAM](#通过-moonraker-更新-ukam)
- [使用方法](#使用方法)
  - [选项](#选项)
- [主机端更新](#主机端更新)
- [编辑 mcus.cfg](#编辑-mcuscfg)
  - [mcus.cfg 示例](#mcuscfg-示例)
    - [RPi 微控制器](#rpi-微控制器)
    - [串口连接（UART）](#串口连接uart)
    - [主板：USB 转 CAN 桥接模式（需要 Katapult）](#主板usb-转-can-桥接模式需要-katapult)
    - [基于 RP2040 的开发板](#基于-rp2040-的开发板)
    - [主板：USB 连接](#主板usb-连接)
    - [工具头：CAN 总线（需要 Katapult）](#工具头can-总线需要-katapult)
    - [换刀系统：USB 连接](#换刀系统usb-连接)
    - [非 Klipper 固件](#非-klipper-固件)
- [关于备份](#关于备份)
- [常见问题](#常见问题)

## 免责声明

> [!WARNING]
> **此脚本不能代替你的判断。如果你不了解如何刷写开发板，请先阅读相关资料。**
>
> 这个提醒可能有些直白。可供参考的刷写指南很多，无法在此一一列出；以下是本脚本编写时参考的资料：
>
> - Klipper 文档
>   - [构建和刷写微控制器](https://www.klipper3d.org/Installation.html#building-and-flashing-the-micro-controller)
>   - [构建和安装 Linux 主机微控制器代码](https://www.klipper3d.org/Beaglebone.html#building-and-installing-linux-host-micro-controller-code)
>   - [SD 卡更新](https://www.klipper3d.org/SDCard_Updates.html)
>   - [进入引导加载程序](https://www.klipper3d.org/Bootloader_Entry.html)
> - [maz0R CAN 总线指南](https://maz0r.github.io/klipper_canbus/)
> - 厂商文档
> - 其他资料
>
> Esoterical 的 [CAN 总线指南](https://canbus.esoterical.online/) 和 [USB 指南](https://usb.esoterical.online/) 目前是固件安装的权威参考。

## UKAM 的功能

根据本机当前的 Klipper/Kalico 源码，为每个已配置的 MCU 构建并刷写固件。UKAM 不会修改 Klipper/Kalico 仓库。

![流程图](./images/flowchart.png)

基本执行流程：

```
service klipper stop
make clean
make menuconfig
make
<刷写命令>
service klipper start
```

> [!IMPORTANT]
> 使用 UKAM 前，请先通过 KIAUH 或其他方式将 Klipper/Kalico 更新到要使用的版本。

## 安装

```
cd ~
git clone https://github.com/jacksky6/update_klipper_and_mcus.git ukam
```

首次运行以下命令时，UKAM 会提示本机尚未初始化，并询问是否创建所需目录和示例 `mcus.cfg`：

```
cd ukam
./ukam.sh
```

确认初始化后，UKAM 不会更新 Klipper 或刷写 MCU，而是提示编辑 `~/printer_data/config/ukam/mcus.cfg`。完成配置后再次运行 UKAM，即可进入 MCU 固件管理菜单。

## 通过 Moonraker 更新 UKAM

将以下内容加入 `moonraker.conf`：

```
[update_manager update_klipper_and_mcus]
type: git_repo
primary_branch: main
path: ~/ukam
origin: https://github.com/jacksky6/update_klipper_and_mcus.git
is_system_service: False
```

## 使用方法

在终端运行 `~/<脚本目录>/ukam.sh` 时，工具会先检查自身是否有新版本；检测到新版本后会询问是否更新。确认更新时仅使用 `git pull --ff-only` 更新本工具，更新成功后会自动重新启动；本地存在未合并改动时不会覆盖文件。随后会显示 MCU 固件状态表，不会立即刷写。表中会列出 `mcus.cfg` 的全部已配置 MCU、当前固件版本、本机 Klipper/Kalico 对应的目标版本及更新状态。

在菜单中输入 MCU 前的序号可更新单个设备；输入 `a` 可更新全部需要更新的 MCU；输入 `r` 刷新版本列表；输入 `q` 退出。单个或批量更新结束后，UKAM 会刷新列表并回到菜单。

选择版本已匹配的单个 MCU 时，UKAM 会询问是否仍要强制重刷。选择 `a` 批量更新时，版本已匹配的 MCU 会被跳过。

可用选项如下。

### 选项

#### `-h`、`--help`：显示用法

```
用法：ukam.sh [<config_file>] [-h]

UKAM 是一个 Klipper MCU 固件更新脚本。

可选参数：<config_file> 指定使用的配置文件，默认为 'mcus.cfg'
  -m, --menuconfig           为所有 MCU 显示 menuconfig（默认不显示）。
  -v, --verbose              用于调试，显示已解析的配置。
  -h, --help                 显示此帮助信息并退出。
```

#### `-m`、`--menuconfig`

在构建固件前执行 `make menuconfig`。不带此选项时，只有在 MCU 的配置文件不存在时才会显示 `menuconfig`。

## 主机端更新

UKAM 不管理 Klipper、Moonraker、Mainsail 或 Fluidd 的安装、更新和回滚。建议使用 [KIAUH](https://github.com/dw-0/kiauh) 统一管理这些主机端组件；完成 Klipper/Kalico 更新后，再运行 UKAM 更新需要匹配版本的 MCU 固件。

## 编辑 mcus.cfg

`mcus.cfg` 包含以下内容：

- **节（section）：** 方括号 `[]` 中为 MCU 自定义的名称，不一定与 Klipper 配置中的名称相同。
- `klipper_section`：不带方括号的 Klipper 节名称，用于跟踪 MCU 固件版本。_提示：也可以在 `mcus.cfg` 中使用与 Klipper 相同的节名称。_

> [!NOTE]
> 此项区分大小写。请确保 `klipper_section` 与 Klipper 配置中对应节的大小写完全一致。

- `config_name`（可选）：`menuconfig` 使用的配置文件名称。多个 MCU 条目可共用同一个 `config_name`。参见[换刀系统配置示例](#换刀系统usb-连接)。
- `is_klipper_fw`（可选）：`true|false`，决定是否构建 Klipper 固件。默认情况下，以 `mcu` 开头的节为 `true`，其他类型的节（如 `beacon`、`crampon`、`high_resolution_filament_sensor`、`scanner` 等）为 `false`。参见[非 Klipper 固件示例](#非-klipper-固件)。
- `action_command`（必填）：固件构建后执行的命令，用于准备、刷写或开关 MCU。可以用 `;` 分隔命令，或在同一节中写入多个 `action_command`；它们会按出现顺序执行。
- `quiet_command`：与 `action_command` 相同，但不输出标准输出。

刷写命令取决于 MCU 和所选刷写方式，例如 `dfu-util`、`make flash`、`flashtool`、`flash_sdcard`、`mount/cp/umount` 等。请查阅开发板文档，选择正确的命令。

> [!NOTE]
> ### 关于进入引导加载程序
> 辅助工具可以简化进入引导加载程序的过程（感谢 @beavis）：可使用 `bootloader_serial.py`、`bootloader_usb.py` 或较新的 `enter_bootloader`。
>
> ```
> 用法：enter_bootloader -t <usb|serial|can> -d <serial> [-b baudrate] | -u <canbus_uuid>
>    -t     当前固件的连接类型（serial|usb|can）
>    -d     串口标识，仅用于 serial 和 usb（/dev/ttyAMA0、/dev/serial/by-id/...）
>    -b     波特率；默认值为 250000
>    -u     canbus_uuid（指定后可不提供 -t）
> ```

### mcus.cfg 示例

#### RPi 微控制器

```elixir
# 用于 RPi
[RaspberryPi]
klipper_section: mcu rpi
action_command: make flash
```

_来源：[Klipper 文档](https://www.klipper3d.org/RPi_microcontroller.html#building-the-micro-controller-code)_

#### 串口连接（UART）

```elixir
# 串口 MCU，使用 flash_sdcard
# flash_sdcard.sh 的第二个参数是 CPU 标识。
# 可用值列表见：
# https://github.com/Klipper3d/klipper/blob/master/scripts/spi_flash/board_defs.py

[mcu]
flash_command: ./scripts/flash-sdcard.sh /dev/ttyAMA0 btt-octopus-f446-v1
```

_来源：[Klipper 文档](https://www.klipper3d.org/SDCard_Updates.html)_

```elixir
# 主板使用 bootloader_serial 辅助工具
[spider]
klipper_section: mcu
# RPi GPIO 上的串口 spider
action_command: ~/klippy-env/bin/python3 ~/ukam/bootloader_serial.py /dev/ttyAMA0 250000
action_command: ~/klippy-env/bin/python3 ~/katapult/scripts/flashtool.py -d /dev/ttyAMA0 -b 250000
```

_来源：[Klipper 文档](https://www.klipper3d.org/Bootloader_Entry.html#physical-serial)_

#### 主板：USB 转 CAN 桥接模式（需要 Katapult）

```elixir
# USB 转 CAN 桥接 MCU，使用 Katapult 作为引导加载程序
# 请在下方填入 CAN 总线 UUID 与 USB 序列号
[octopus_usb2can]
klipper_section: mcu
quiet_command: ~/klippy-env/bin/python3 ~/katapult/scripts/flashtool.py -i can0 -r -u <YOUR_CANBUS_UUID>; sleep 2
action_command: ~/klippy-env/bin/python3 ~/katapult/scripts/flashtool.py -d /dev/serial/by-id/usb-katapult_stm32f446xx_<BOARD_ID>-if00

# 使用 enter_bootloader 函数
[octopus_usb2can]
klipper_section: mcu
quiet_command: enter_bootloader -u <YOUR_CANBUS_UUID>
action_command: ~/klippy-env/bin/python3 ~/katapult/scripts/flashtool.py -d /dev/serial/by-id/usb-katapult_stm32f446xx_<BOARD_ID>-if00
```

_来源：[Roguyt_prepare_command 分支](../roguyt_prepare_command/mcus.ini)_

#### 基于 RP2040 的开发板

```elixir
# 用于 Pico RP2040
[pico]
klipper_section: mcu nevermore
# 没有引导加载程序，需要手动进入启动模式
action_command: sudo mount /dev/sda1 /mnt ; sudo cp out/klipper.uf2 /mnt ; sudo umount /mnt

[pico_bootloader]
klipper_section: mcu
# 使用 Katapult 作为引导加载程序
action_command: make flash FLASH_DEVICE=/dev/serial/by-id/usb-Klipper_rp2040_<BOARD_ID>-if00

[pico_bootloader]
klipper_section: mcu
# 使用 Katapult 作为引导加载程序
quiet_command: enter_bootloader -t usb -d /dev/serial/by-id/usb-Klipper_rp2040_<BOARD_ID>-if00
action_command: ~/klippy-env/bin/python3 ~/katapult/scripts/flashtool.py -d /dev/serial/by-id/usb-katapult_rp2040_<BOARD_ID>-if00
```

_来源：原作者未记录。_

#### 主板：USB 连接

```elixir
[catalyst]
klipper_section: mcu
# 通过 bootloader_usb.py 操作 USB 串口上的 catalyst
action_command: ~/klippy-env/bin/python3 ~/ukam/bootloader_usb.py /dev/serial/by-id/usb-Klipper_stm32f401xc_<board_serial>
quiet_command: sleep 1
action_command: ~/klippy-env/bin/python3 ~/katapult/scripts/flashtool.py -d /dev/serial/by-id/usb-katapult_stm32f401xc_<board_serial> -b 250000
```

_来源：[Klipper 文档](https://www.klipper3d.org/Bootloader_Entry.html#python-with-flash_usb)_

```elixir
[catalyst]
klipper_section: mcu
# 通过 make flash 操作 USB 串口上的 catalyst
action_command: make flash FLASH_DEVICE=/dev/serial/by-id/usb-Klipper_stm32f401xc_<board_serial>
```

_来源：[Klipper 文档](https://www.klipper3d.org/RPi_microcontroller.html#building-the-micro-controller-code)_

#### 工具头：CAN 总线（需要 Katapult）

```elixir
[toolhead]
klipper_section: mcu ebb36
action_command: ~/klippy-env/bin/python3 ~/katapult/scripts/flashtool.py -u <canbus_uuid>
```

#### 换刀系统：USB 连接

```elixir
[mcu tool1]
quiet_command: enter_bootloader -t usb -d /dev/serial/by-id/usb-Klipper_rp2040_<BOARD1_ID>-if00
action_command: ~/klippy-env/bin/python3 ~/katapult/scripts/flashtool.py -d /dev/serial/by-id/usb-katapult_rp2040_<BOARD1_ID>-if00

[mcu tool2]
# 与 mcu tool1 共用 menuconfig 配置
config_name: mcu tool1
quiet_command: enter_bootloader -t usb -d /dev/serial/by-id/usb-Klipper_rp2040_<BOARD2_ID>-if00
action_command: ~/klippy-env/bin/python3 ~/katapult/scripts/flashtool.py -d /dev/serial/by-id/usb-katapult_rp2040_<BOARD2_ID>-if00

[mcu toolN]
# 与 mcu tool1 共用 menuconfig 配置
config_name: mcu_tool1
quiet_command: enter_bootloader -t usb -d /dev/serial/by-id/usb-Klipper_rp2040_<BOARDN_ID>-if00
action_command: ~/klippy-env/bin/python3 ~/katapult/scripts/flashtool.py -d /dev/serial/by-id/usb-katapult_rp2040_<BOARDN_ID>-if00
```

_来源：[Issue #10](https://github.com/fbeauKmi/update_klipper_and_mcus/issues/10)_

#### 非 Klipper 固件

```elixir
# Beacon3d
[beacon]
is_klipper_fw: false
quiet_command: sudo systemctl stop klipper
action_command: git -C ~/beacon_klipper pull
action_command: ~/beacon_klipper/update_firmware.py update all

# Cartographer
# 注意：Cartographer 需要 Klipper 正在运行，因此请将本节放在最前面。
[cartographer]
klipper_section: mcu scanner
is_klipper_fw: false
action_command: git -C ~/cartographer_firmware pull
action_command: ~/cartographer_firmware/fw_update.sh

# Crampon ADXL
[crampon]
klipper_section: mcu crampon
is_klipper_fw: false
action_command: git -C ~/crampon_anchor pull
action_command: ~/crampon_anchor/update.sh
```

_来源：[Issue #12](https://github.com/fbeauKmi/update_klipper_and_mcus/issues/12)_

## 关于备份

常见的打印机配置和历史记录备份方式，是保存 `~/printer_data` 目录。为方便备份，UKAM 会在 `~/printer_data/ukam` 创建一个符号链接。

> [!TIP]
> Armchair-Engineering 的 [Klipper-backup](https://github.com/Armchair-Heavy-Industries/klipper-backup) 可将打印机配置轻松备份到 GitHub 并恢复。

## 常见问题

**问：可以重命名一个节吗？**
答：可以，但如果不同时重命名 `~/printer_data/config/ukam` 中对应的配置文件，会丢失 MCU 配置，之后运行 UKAM 时会再次显示 `menuconfig`。

> [!TIP]
> 配置名称中的空格会转换为下划线。

**问：MCU 刷写失败，该怎么办？**
答：确认 `mcus.cfg` 配置正确。检查开发板状态，具体取决于连接方式；`lsusb` 和 `flashtool.py` 是常用工具。如果开发板可见，再次运行 `./ukam.sh`。

**问：UKAM 会更新 Katapult 吗？**
答：不会。通常没有必要更新引导加载程序。

**问：为什么 UKAM 显示发生错误，但刷写似乎已经完成？**
答：在 USB 模式下，即使刷写成功，`dfu-util` 也总会返回错误码。目前无法消除这个错误；可以使用其他刷写方式（例如 Katapult）来避免它。
