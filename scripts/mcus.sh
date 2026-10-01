#!/bin/bash

# Define an associative arrays "flash_actions", "klipper_section", "mcu_version", "config_name"
declare -A flash_actions
declare -A klipper_section
declare -A mcu_version
declare -A config_name
declare -A is_klipper_fw
declare -A mcu_app
# Define an indexed array "mcu_order" to store the order of MCUs in mcus.cfg
mcu_order=()

BUILD_ERROR=false

# Define a function to initialize the flash_actions array from the config file
function load_mcus_config() {
  filename=${CONFIG:-$ukam_config/mcus.cfg}
  if [[ -f "$filename" ]]; then
    file_content=$(tr '\r' '\n' <"$filename")

    while IFS==: read -r key value; do
      key=$(xargs <<<"$key")
      value=$(xargs <<<"$value")
      case "$key" in
      \[*\])
        section=${key#[}
        section=${section%]}

        # Check if section already exists
        for existing_section in "${mcu_order[@]}"; do
          [[ "$existing_section" == "$section" ]] &&
            error_exit "在 $filename 中发现重复的节 [$section]"
        done

        # Store the order of MCUs in mcu_order array
        mcu_order+=("$section")
        # Set default values
        config_name["$section"]=$section
        mcu_version["$section"]=unknown
        mcu_app["$section"]=unknown
        ;;
      flash_command | quiet_command | action_command)
        # Suppress stdout for quiet_command, while keeping stderr visible.
        if [[ $key == quiet_command ]]; then
          value="$value >/dev/null"
        fi

        # append command to string
        if [ -n "${flash_actions["$section"]}" ]; then
          flash_actions["$section"]="${flash_actions["$section"]};$value"
        else
          flash_actions["$section"]="$value"
        fi
        ;;
      klipper_section)
        klipper_section["$section"]=$value
        ;;
      config_name)
        config_name["$section"]=$value
        ;;
      is_klipper_fw)
        case ${value,,} in
        true) value=true ;;
        false) value=false ;;
        *) error_exit "is_klipper_fw 必须为 true 或 false" ;;
        esac
        is_klipper_fw["$section"]=$value
        ;;
      *)
        [[ -z "$key" || "$key" =~ ^# ]] && continue
        error_exit "'$key' 不是有效的配置键"
        ;;
      esac
    done <<<"$file_content"

    for mcu in "${mcu_order[@]}"; do
      if [[ -z "${flash_actions[$mcu]}" ]]; then
        error_exit "未找到 $mcu 的操作命令，请检查配置文档"
      fi
      # Set default values for klipper_section and is_klipper_fw
      if [[ -z "${klipper_section[$mcu]}" ]]; then
        klipper_section["$mcu"]=$mcu
        if [[ -z "${is_klipper_fw[$mcu]}" ]]; then
          is_klipper_fw["$mcu"]=true
        fi
      fi
    done

    return 0
  fi
}

function set_is_klipper_fw() {
  mcu=$1
  if [[ -z ${is_klipper_fw["$mcu"]} ]]; then
          is_klipper_fw["$mcu"]=false
          if [[ "${klipper_section["$mcu"]}" =~ ^mcu\s* ]]; then
            is_klipper_fw["$mcu"]=true
          fi
  fi
}

# show config datas
function show_config() {
  if $VERBOSE; then
      echo -e "\n${BLUE}------- MCU 配置信息 -------${DEFAULT}"
      for mcu in "${mcu_order[@]}"; do
        set_is_klipper_fw "$mcu"
        echo -e "${RED}[$mcu]${DEFAULT}" \
          "\n ${GREEN}config_name:${DEFAULT} ${config_name[$mcu]}" \
          "\n ${GREEN}klipper_section:${DEFAULT} ${klipper_section[$mcu]}" \
          "\n ${GREEN}mcu_app:${DEFAULT} ${mcu_app[$mcu]}" \
          "\n ${GREEN}mcu_version:${DEFAULT} ${mcu_version[$mcu]}" \
          "\n ${GREEN}is_klipper_fw:${DEFAULT} ${is_klipper_fw[$mcu]}" \
          "\n ${GREEN}commands:${DEFAULT} ${flash_actions[$mcu]}\n"  
      done
      echo -e "${BLUE}------------------------------${DEFAULT}"
    fi
}

# Define a function to update the firmware on the MCUs
function update_mcus() {
  local selected_mcu="$1"
  local force_reflash
  
  if [ ${#mcu_order[@]} -eq 0 ]; then
    echo -e "${RED}未在 $filename 中找到已配置的 MCU。${DEFAULT}"
    return 0
  fi
  # Loop over the keys (MCUs) in the flash_actions array
  for mcu in "${mcu_order[@]}"; do
    [[ -n "$selected_mcu" && "$mcu" != "$selected_mcu" ]] && continue
    set_is_klipper_fw "$mcu"
    force_reflash=false
    
    # Initiate variables for current mcu
    SHOW_MENUCFG=$MENUCONFIG
    SHARED_CONFIG=false
    BUILD_FIRMWARE=${is_klipper_fw["$mcu"]}
    version="${mcu_version["$mcu"]}"
    def=y

    [ -n $version ] && mcu_str="$mcu [${klipper_section["$mcu"]}]" \
      || mcu_str="$mcu"

    if $BUILD_FIRMWARE; then
      # Check version
      if [[ "$version" == "$k_local_version" ]]; then
        echo "${WHITE}$mcu_str${MAGENTA} 当前固件：${GREEN}$version(${mcu_app[$mcu]})"
        if [[ -n "$selected_mcu" ]]; then
          if prompt "固件版本已匹配，仍要强制刷写吗？" n; then
            force_reflash=true
          else
            continue
          fi
        else
          echo -e "${GREEN}固件版本已匹配，跳过刷写。${DEFAULT}"
          continue
        fi
      elif [ -n $version ]; then
        echo -e "$mcu_str 当前固件：${GREEN}${version}(${mcu_app[$mcu]})" \
          "${DEFAULT} -> 目标版本：${GREEN}$k_local_version(${APP})${DEFAULT}。"
        if [[ "${mcu_app[$mcu]}" == "unknown" || "$APP" == "${mcu_app[$mcu]}" ]]; then
          printf '%s\n' "$k_local_version" "$version" | sort -V -C && def=n \
            && echo -e "${RED}即将刷写较旧的固件版本！${DEFAULT}"
        fi 
      fi
      
      # Set config_file in the scripts directory
      target=$(echo ${config_name["$mcu"]} | tr ' ' '_')
      [ "${config_name["$mcu"]}" != "$mcu" ] && SHARED_CONFIG=true
      config_path="$ukam_config/config/config.$target"
      config_file_str="KCONFIG_CONFIG=$config_path"
      # showmenu
      if [[ ! -f $config_path ]]; then
        SHOW_MENUCFG=true
      fi
    else
      [ -n $version ] && echo -e "$mcu_str 当前固件：${GREEN}${version}(${mcu_app[$mcu]})" \
      "${DEFAULT}"
    fi

    # Prompt the user whether to update this MCU
    if ! $force_reflash && ! prompt "是否更新 ${WHITE}$mcu_str${MAGENTA} 的固件？" $def; then
      continue
    fi


    # build firmware for Klipper
    if $BUILD_FIRMWARE; then
      # Stop Klipper before building firmware; some non-Klipper firmware scripts require Klipper running
      klipperservice stop
      # Change to the Klipper directory
      cd ~/klipper
      # Clean the previous build and configure for the selected MCU
      make clean $config_file_str
      # Open menuconfig if needed
      $SHOW_MENUCFG && make menuconfig $config_file_str

      # Check if forged ID is present in config file for shared config
      if $SHARED_CONFIG; then
        while grep -q -E "# CONFIG_USB_SERIAL_NUMBER_CHIPID|\
# CONFIG_CAN_UUID_USE_CHIPID" $config_path; do
          echo -e "${RED}伪造的串口/CAN 总线 ID 与" \
            "config_name 选项不兼容。${DEFAULT}"
          if prompt "现在修改 menuconfig？"; then
            make menuconfig $config_file_str
          else
            error_exit "使用 config_name 时不能伪造串口或 CAN 总线 ID"
          fi
        done
      fi
      
      BUILD_ERROR=false
      trap 'build_error $LINENO' ERR
      # Check CPU thread number (added by @roguyt to build faster)
      CPUS=$(grep -c ^processor /proc/cpuinfo)
      make -j $CPUS $config_file_str
      trap 'handle_error $LINENO' ERR
    fi

    if ! $BUILD_ERROR && { ! $SHOW_MENUCFG || prompt "按 [Y] 刷写 $mcu_str"; }; then
      # Split the flash command string into separate commands and run each one
      IFS=";" read -ra commands <<<"${flash_actions["$mcu"]}"
      for command in "${commands[@]}"; do
        # Check if the command contains "make flash"
        if [[ "$command" == *"make flash"* ]]; then
          # Add KCONFIG_CONFIG=config/$mcu after "make flash"
          command="${command/make\ flash/make\ flash\ $config_file_str}"
        fi
        [[ ! "$command" =~ ">/dev/null" ]] &&
          echo "执行命令：$command"
        eval "$command"
      done
    fi
  done
  return 0
}

# Handle build error() {
function build_error() {
  BUILD_ERROR=true
  echo -e "${RED}!!错误：固件构建失败，跳过刷写。$*${DEFAULT}\n" >&2
}

function reset_mcu_versions() {
  for mcu in "${mcu_order[@]}"; do
    mcu_version["$mcu"]=unknown
    mcu_app["$mcu"]=unknown
  done
}

function refresh_mcu_versions() {
  reset_mcu_versions
  get_mcus_version
}

function show_mcu_update_menu() {
  local choice
  local index
  local mcu
  local current_version
  local target_version
  local status

  while true; do
    clear 2>/dev/null
    ui_rule
    echo -e "${CYAN}  Klipper固件自动刷写工具${DEFAULT}"
    echo "  本机 Klipper/Kalico 版本：${k_local_version}"
    ui_rule
    echo ""

    if [ ${#mcu_order[@]} -eq 0 ]; then
      echo -e "${YELLOW}未在 $filename 中找到已启用的 MCU 配置。${DEFAULT}"
      echo "请编辑 ~/printer_data/config/ukam/mcus.cfg 后重新运行。"
      read -r -p "输入 q 退出：" choice
      [[ "${choice,,}" == "q" ]] && return 0
      continue
    fi

    printf '%-5s %-20s %-26s %-26s %s\n' \
      "序号" "MCU" "当前固件版本" "目标固件版本" "状态"
    printf '%0.s─' {1..100}
    echo ""

    index=1
    for mcu in "${mcu_order[@]}"; do
      set_is_klipper_fw "$mcu"
      current_version="${mcu_version[$mcu]}"
      target_version="-"
      status="外部固件"

      if ${is_klipper_fw["$mcu"]}; then
        target_version="$k_local_version"
        if [[ "$current_version" == "unknown" ]]; then
          current_version="未读取"
          status="无法判断"
        elif [[ "$current_version" == "$k_local_version" ]]; then
          status="已匹配"
        else
          status="需要更新"
        fi
      elif [[ "$current_version" == "unknown" ]]; then
        current_version="未读取"
      fi

      printf '%-5s %-20s %-26s %-26s %s\n' \
        "$index" "$mcu" "$current_version" "$target_version" "$status"
      ((index++))
    done

    echo ""
    ui_rule
    echo -e "${CYAN}  操作${DEFAULT}"
    echo "  [序号]  更新指定 MCU"
    echo "  [A]     更新全部需要更新的 MCU"
    echo "  [R]     刷新版本列表"
    echo "  [Q]     退出"
    ui_rule
    read -r -p "  请输入选项：" choice

    case "${choice,,}" in
    q)
      return 0
      ;;
    r)
      refresh_mcu_versions
      ;;
    a)
      update_mcus
      klipperservice start
      echo "等待 MCU 重启完成，5 秒后刷新固件版本..."
      sleep 5
      refresh_mcu_versions
      ;;
    '')
      ;;
    *)
      if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && \
        ((10#$choice <= ${#mcu_order[@]})); then
        mcu="${mcu_order[$((10#$choice - 1))]}"
        update_mcus "$mcu"
        klipperservice start
        echo "等待 MCU 重启完成，5 秒后刷新固件版本..."
        sleep 5
        refresh_mcu_versions
      else
        echo -e "${RED}无效选择，请重新输入。${DEFAULT}"
        sleep 1
      fi
      ;;
    esac
  done
}
