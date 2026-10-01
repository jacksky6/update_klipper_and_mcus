#!/bin/bash

function moonraker_query() {
  local key=$2
  local object=$(echo "$1" | sed 's/ /%20/g')
  moonraker_object=http://127.0.0.1:7125/
  eval "$key=\$( curl -s \"$moonraker_object$object\" )"
  [[ ! $(echo ${!key} | grep -o '"result":') == '"result":' ]] && return 1
  return 0
}

function parse_json() {
  local value=$(echo "$json" | grep -o "\"$1\":[ ]*\"[^\"]*" | cut -d'"' -f4)
  # Use eval to assign the value to the variable name passed as $2
  # if value doesn't exist, assign $3
  # if $3 is not set, return 1
  [ -z "$value" ] && [ -z "$3" ] && return 1
  eval "$2=\"${value:-$3}\""
  return 0
}

function list_mcus() {
  local -n result=$1 # Use nameref for indirect reference
  local pattern=$( IFS='|'; echo "(mcu )*(${klipper_section[*]})" ) # build pattern
  IFS=';'
  # Use mapfile to read the output of grep and sed directly into an array
  mapfile -t result < <(echo "$json" | grep -oP '"(mcu|'$pattern')"' | sed 's/"//g')

  [[ ${#result[@]} -eq 0 ]] && return 1
  return 0
}

function get_venv() {
  if ! moonraker_query printer/info json; then
    return 1
  fi
  parse_json python_path KLIPPER_VENV
  return 0
  
}

function get_mcus_version() {
  # Check if printer info is available
  if ! moonraker_query printer/info json; then
    echo -e "${RED}无法访问 Moonraker，无法读取 MCU 固件信息。${DEFAULT}"
    return 0
  fi
  
  parse_json app APP "Klipper"

  parse_json state printer_state "error"
  # Abort if printer is startup or error
  if [[ $printer_state =~ ^(startup)$ ]]; then
    echo -e "${RED}Klippy 状态：${printer_state}。无法读取 MCU 固件版本。${DEFAULT}"
    return 0
  fi

  # Check printer state
  if ! moonraker_query printer/objects/query?print_stats json; then
    echo -e "${RED}Klippy 状态：${printer_state}。无法读取 MCU 固件版本。${DEFAULT}"
    return 0
  fi  
  parse_json state klipper_state "error"
  if [[ $klipper_state =~ ^(printing|paused)$ ]]; then
    error_exit "打印机当前为 ${klipper_state} 状态，禁止更新 MCU 固件！"
    return 0
  fi

  # Get MCU list and versions
  moonraker_query printer/objects/list json
  if ! list_mcus mcus; then
    echo -e "${RED}Klippy 状态：${printer_state}。无法获取 MCU 列表。${DEFAULT}"
    return 0
  fi
    
  for mcu in "${mcus[@]}"; do
    moonraker_query "printer/objects/query?$mcu" json
    parse_json mcu_version tmp "unknown"
    parse_json app app "unknown"
    if [[ $tmp == "unknown" ]]; then
      echo -e "${RED}Klippy 状态：${printer_state}。无法读取 ${mcu} 的固件版本。${DEFAULT}"
      return 0
    fi

    for cmcu in "${mcu_order[@]}"; do
      mcu_section=${klipper_section["$cmcu"]}
      if [[ $mcu == "$mcu_section" || $mcu == "mcu ${mcu_section}" ]]; then
        klipper_section["$cmcu"]=$mcu
        mcu_version["$cmcu"]=$tmp
        mcu_app["$cmcu"]=$app
      fi
    done
  done

  return 0
}
