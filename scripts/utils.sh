#!/bin/bash

usage() {
  cat <<EOF
用法：$0 [<mcus.ini>] [-h]

UKAM：Klipper 固件更新脚本，用于更新 Klipper 仓库和 MCU 固件。

可选参数：<config_file> 指定使用的配置文件，默认为 'mcus.ini'
  -c, --checkonly   仅检查 Klipper 是否为最新版本。
  -b, --rebase      使用 rebase 而非 fast-forward 更新 Klipper。
  -f, --firmware    不合并仓库更新，强制更新固件。
  -m, --menuconfig  为所有 MCU 显示 menuconfig（默认不显示）。
  -r, --rollback    回滚到之前的版本。
  -q, --quiet       静默模式：自动执行所需操作，跳过 MENUCONFIG！
  -v, --verbose     用于调试，显示已解析的配置。
  -h, --help        显示此帮助信息并退出。
EOF
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

  # In quiet mode skip prompt and return default value
  $QUIET && { [ $default = "yN" ] && return 1 || return 0; }  
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
  echo -e "${RED}!!Error: $*${DEFAULT}" >&2
  exit 1
}

# Handle unexpected error() {
function handle_error() {
  ERROR=true
  echo -e "${RED}!!Error: Unexpected error $*${DEFAULT}" >&2
  $QUIET && exit 1  # Exit on any error if in quiet mode
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
    \?) error_exit "Invalid option -$OPTARG. Usage: enter_bootloader -t" \
      "<usb|serial|can> -d <serial> [-b baudrate] | -u <canbus_uuid>" ;;
    :) error_exit "Option -$OPTARG requires an argument. Usage:" \
      "enter_bootloader -t <usb|serial> -d <serial> [-b baudrate] |" \
      "-u <canbus_uuid>" ;;
    esac
  done

  # Check if required arguments are provided
  if [[ -z "$type" ]]; then
    error_exit "Type argument is missing. Usage: enter_bootloader" \
      "-t <usb|serial> -d <serial> [-b baudrate]"
  fi

  if [[ -z "$serial" ]]; then
    error_exit "Serial argument is missing. Usage: enter_bootloader" \
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
    echo "Entering serial bootloader mode for $serial"
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
    echo "Entering CAN bootloader mode for $serial"
    if [[ -f ~/katapult/scripts/flashtool.py ]]; then
      ~/katapult/scripts/flashtool.py -r -u $serial
      sleep 2
    else
      error_exit "flashtool.py not found"
    fi
    ;;
  *)
    error_exit "Unknown bootloader type: $type"
    ;;
  esac
}

function link_config() {
  if [ ! -d $ukam_config ]; then
    mkdir $ukam_config
    echo -e "\n${DEFAULT}Create folder ${ukam_config}"
    #link existing folder (compatibity with previous version)
    if [ -d $ukam_path/config ]; then
      ln -s $ukam_path/config $ukam_config/config
    fi
    if [ -e $ukam_path/mcus.ini ]; then
      echo -e "${DEFAULT}Moving mcus.ini to ${ukam_config}\n"
      mv $ukam_path/mcus.ini $ukam_config
    else
      echo -e "${DEFAULT}Copying sample mcus.ini to ${ukam_config}\n"
      cp $ukam_path/examples/mcus.ini $ukam_config
    fi
  fi
  if [ ! -d "$ukam_config/config" ]; then
      # If it doesn't exist, create it
      mkdir -p "$ukam_config/config"
      echo -e "${DEFAULT}Create folder $ukam_config/config\n"
  fi
}
