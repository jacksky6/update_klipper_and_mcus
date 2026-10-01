#!/bin/bash

# UKAM is a bash script to simplify Klipper MCU firmware updates.
#
# Copyright (C) 2024-2025 fboc (Frédéric Beaucamp)
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with
# this program. If not, see http://www.gnu.org/licenses/.

# Exit on error
set -E

trap 'handle_error $LINENO' ERR
# Get Current script fullpath
ukam_path=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
# Config_path
ukam_config="${HOME}/printer_data/config/ukam"

#Load functions
source "$ukam_path/scripts/utils.sh"
source "$ukam_path/scripts/mcus.sh"
source "$ukam_path/scripts/klipper.sh"
source "$ukam_path/scripts/moonraker.sh"

# Display versions
ukam_version() {
  git -C $ukam_path fetch -q
  git -C $ukam_path fetch --tags --force -q
  s_version=$(git -C $ukam_path describe --always --tags --long --dirty \
    2>/dev/null)
  s_remote=$(git -C $ukam_path describe "origin/$(git -C $ukam_path rev-parse \
    --abbrev-ref HEAD)" --always --tags --long 2>/dev/null)
  [[ ! $s_version = "" ]] && echo -e "  当前版本：$s_version"
  [[ ! $s_version = "$s_remote"* ]] &&
    echo -e "  有可用新版本：$s_remote"
  return 0
}

function splash() {
  echo -e "${LIGHT_MAGENTA}
  ++${CYAN}      __  ____ __ ___    __  ___  ${LIGHT_MAGENTA}++
  | ${GREEN}     / / / / //_//   |  /  |/  /  ${LIGHT_MAGENTA} |
  | ${BLUE}    / / / / ,<  / /| | / /|_/ /   ${LIGHT_MAGENTA} |
  | ${MAGENTA}   / /_/ / /| |/ ___ |/ /  / /    ${LIGHT_MAGENTA} |
  | ${RED}   \____/_/ |_/_/  |_/_/  /_/     ${LIGHT_MAGENTA} |          
  |  ${WHITE}Klipper固件自动刷写工具${LIGHT_MAGENTA}  |
  ++${WHITE}          中文维护版          ${LIGHT_MAGENTA}++
  "
  ukam_version
}

# Define the main function
function main() {
  if [[ ! -f "$ukam_config/mcus.cfg" ]]; then
    echo ""
    ui_rule
    echo -e "${CYAN}  首次运行初始化${DEFAULT}"
    ui_rule
    echo "  检测到这是首次运行，本机尚未初始化本工具。"
    echo "  将创建配置目录并安装示例配置文件："
    echo "  $ukam_config/mcus.cfg"
    echo ""

    if ! prompt "是否现在初始化？"; then
      echo -e "${YELLOW}  已取消初始化，未修改任何文件。${DEFAULT}"
      return 0
    fi

    echo ""
    link_config
    echo ""
    ui_rule
    echo -e "${GREEN}  初始化完成${DEFAULT}"
    ui_rule
    echo "  请编辑以下文件，填写 MCU 的刷写配置："
    echo "  $ukam_config/mcus.cfg"
    echo ""
    echo "  配置完成后，再次运行：./ukam.sh"
    echo ""
    return 0
  fi

  link_config
  get_klipper_vars
  load_mcus_config
  get_mcus_version
  show_config

  show_mcu_update_menu

  if $ERROR; then
    echo -e "\n    ${RED}操作过程中发生错误。"
    echo -e "       请检查上方日志后重试。\n${DEFAULT}"

    exit 1
  fi

  echo -e "\n    ${GREEN}操作结束。\n${DEFAULT}"

  exit 0
}

if [ "$EUID" -eq 0 ]; then
  echo -e "${RED}请不要以 root 用户运行本工具！" >&2
  exit 1
fi

HELP=false
MENUCONFIG=false
VERBOSE=false
APP=unknown

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help) HELP=true ;;
  -m | --menuconfig) MENUCONFIG=true ;;
  -v | --verbose) VERBOSE=true ;;
  -* | --*) HELP=true ;;
  *)
    CONFIG=$1
    ;;
  esac
  shift
done

# Call usage function if --help or -h is specified
[[ $HELP == true ]] && usage && exit 0

splash
main
