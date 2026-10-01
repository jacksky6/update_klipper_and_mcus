#!/bin/bash

# Check if the Klipper service is running and save the result in
# "klipperstate"
klipperstate=$(systemctl is-active klipper >/dev/null 2>&1 && echo true ||
  echo false)

# Initialize local Klipper version information used for MCU firmware matching.
k_local_version=""
k_local_name="MCU 固件源码"

# Load the local Klipper version. UKAM never modifies the Klipper repository.
function get_klipper_vars() {
  k_local_version=$(git -C ~/klipper describe --tags --always --long --dirty)

  local origin_url
  origin_url=$(git -C ~/klipper remote get-url origin 2>/dev/null)
  case "${origin_url,,}" in
  *kalico*) k_local_name="Kalico" ;;
  *klipper*) k_local_name="Klipper" ;;
  esac
}
# Check if Klipper venv exists
function find_klipper_venv() {
  if get_venv; then
    echo KLIPPER_VENV
    return 0
  fi

  local venv_dir="$HOME/klippy-env"
  if [ -d "$venv_dir" ]; then
    echo "$venv_dir/bin/python"
  else
    error_exit "未在 $venv_dir 找到 Python 虚拟环境"
  fi
}

# Define a function to start or stop the Klipper service
function klipperservice {
  # Check if the Klipper service is running and save the result in
  # "klipperrunning"
  klipperrunning=$(systemctl is-active klipper >/dev/null 2>&1 &&
    echo true || echo false)

  ! $klipperstate && return 0
  [[ "$1" = "start" ]] && str="ing" && $klipperrunning && return 0
  [[ "$1" = "stop" ]] && str="ping" && ! $klipperrunning && return 0
  klipperrunning=false
  if $ERROR && ! prompt "${RED}操作发生错误！
仍要重启 ${APP} 吗？" n; then
   return 0
  fi
  [[ "$1" = "start" ]] && action="启动" || action="停止"
  echo -e "${YELLOW}${action} Klipper 服务${DEFAULT}"
  sudo systemctl $1 klipper
  return 0
}
