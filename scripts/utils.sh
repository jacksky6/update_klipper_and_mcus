#!/bin/bash

usage() {
  cat <<EOF
用法：$0 [<config_file>] [-h]

UKAM：Klipper MCU 固件更新脚本。

可选参数：<config_file> 指定使用的配置文件，默认为 'mcus.cfg'
  -m, --menuconfig  为所有 MCU 显示 menuconfig（默认不显示）。
  -v, --verbose     用于调试，显示已解析的配置。
  -h, --help        显示此帮助信息并退出。
EOF
}

function ui_rule() {
  printf '%0.s━' {1..76}
  printf '\n'
}

# Colors helpers
RED=$'\033[1;31m'
GREEN=$'\033[1;32m'
YELLOW=$'\033[0;33m'
BLUE=$'\033[1;34m'
MAGENTA=$'\033[0;35m'
LIGHT_MAGENTA=$'\033[1;35m'
CYAN=$'\033[0;36m'
WHITE=$'\033[0;37m'
DEFAULT=$'\033[0m'

# Error handler
ERROR=false

# Define a function to prompt the user with a y/n question
prompt() {
  local default="Yn"
  [ $# -eq 2 ] && [ ${2^} = "N" ] && default="yN"

  while true; do
    read -p "${MAGENTA}$1 [$default]: ${DEFAULT}" yn
    case $yn in
    [Yy]*) return 0 ;;
    "")
      [ $default = "yN" ] && return 1 # Return 1 if N, 0 if Y is default
      return 0 # Return 0 on Enter key press (Y as default)
      ;; 
    [Nn]*) return 1 ;;
    esac
    line_count=$(echo $1 | wc -l)
    for ((i=0; i<$line_count; i++)); do
      echo -ne '\e[1A\e[K' # Move cursor up and clear line
    done
  done
}

# Error function Exit script
function error_exit() {
  echo -e "${RED}!!错误：$*${DEFAULT}" >&2
  exit 1
}

# Handle unexpected error() {
function handle_error() {
  ERROR=true
  echo -e "${RED}!!错误：发生意外错误 $*${DEFAULT}" >&2
}
# Function to enter bootloader mode
# Usage  : enter_bootloader -t [type:usb|serial|can] -d [serial]
#                           -u [canbus_uuid] -b [baudrate]
function enter_bootloader() {
  local type=""
  local serial=""
  local baudrate=""
  local OPTIND=1

  # Parse command-line options
  while getopts ":t:d:b:u:" opt; do
    case $opt in
    u)
      type='can'
      serial="$OPTARG"
      ;;
    t) type=$(echo "$OPTARG" | tr '[:upper:]' '[:lower:]') ;;
    d) serial="$OPTARG" ;;
    b) baudrate="$OPTARG" ;;
    \?) error_exit "无效选项 -$OPTARG。用法：enter_bootloader -t" \
      "<usb|serial|can> -d <serial> [-b baudrate] | -u <canbus_uuid>" ;;
    :) error_exit "选项 -$OPTARG 需要参数。用法：" \
      "enter_bootloader -t <usb|serial> -d <serial> [-b baudrate] |" \
      "-u <canbus_uuid>" ;;
    esac
  done

  # Check if required arguments are provided
  if [[ -z "$type" ]]; then
    error_exit "缺少类型参数。用法：enter_bootloader" \
      "-t <usb|serial> -d <serial> [-b baudrate]"
  fi

  if [[ -z "$serial" ]]; then
    error_exit "缺少串口参数。用法：enter_bootloader" \
      "-t <usb|serial> -d <serial> [-b baudrate] | -u <canbus_uuid>"
  fi

  venv=$(find_klipper_venv)

  case "$type" in
  usb)
    cd ~/klipper/scripts
    $venv -c "import flash_usb as u; u.enter_bootloader('$serial')"
    sleep 2
    ;;
  serial)
    echo "正在让 $serial 进入串口引导加载程序模式"
    baudrate=${baudrate:-250000}
    $venv -c "
import sys, serial
try:
    with serial.Serial('$serial', int($baudrate), timeout=1) as ser:
        ser.write(b'~ \x1c Request Serial Bootloader!! ~')
except serial.SerialException as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
"
    sleep 2
    ;;
  can)
    echo "正在让 $serial 进入 CAN 引导加载程序模式"
    if [[ -f ~/katapult/scripts/flashtool.py ]]; then
      ~/katapult/scripts/flashtool.py -r -u $serial
      sleep 2
    else
      error_exit "未找到 flashtool.py"
    fi
    ;;
  *)
    error_exit "未知的引导加载程序类型：$type"
    ;;
  esac
}

function link_config() {
  if [ ! -d "$ukam_config" ]; then
    mkdir -p "$ukam_config"
    echo -e "${GREEN}  已创建配置目录：${DEFAULT}$ukam_config"
  fi

  if [ ! -f "$ukam_config/mcus.cfg" ]; then
    cp "$ukam_path/examples/mcus.cfg" "$ukam_config/mcus.cfg"
    echo -e "${GREEN}  已复制示例 mcus.cfg 配置。${DEFAULT}"
  fi

  if [ ! -d "$ukam_config/config" ]; then
    if [ -d "$ukam_path/config" ]; then
      ln -s "$ukam_path/config" "$ukam_config/config"
    else
      mkdir -p "$ukam_config/config"
    fi
    echo -e "${GREEN}  已创建固件配置目录。${DEFAULT}"
  fi
}
