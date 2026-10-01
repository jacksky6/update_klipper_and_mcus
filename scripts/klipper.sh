#!/bin/bash

# Check if the Klipper service is running and save the result in
# "klipperstate"
klipperstate=$(systemctl is-active klipper >/dev/null 2>&1 && echo true ||
  echo false)

# Initialize local Klipper version information used for MCU firmware matching.
k_local_version=""

# Load the local Klipper version. UKAM never modifies the Klipper repository.
function get_klipper_vars() {
  k_local_version=$(git -C ~/klipper describe --tags --always --long --dirty)
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
    error_exit "virtual-env not found at $venv_dir"
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
  if $ERROR && ! prompt "${RED}An error occured !
Do you want to restart ${APP} anyway ?" n; then
   return 0
  fi
  echo -e "${YELLOW}${1^}$str Klipper service${DEFAULT}"
  sudo systemctl $1 klipper
  return 0
}
