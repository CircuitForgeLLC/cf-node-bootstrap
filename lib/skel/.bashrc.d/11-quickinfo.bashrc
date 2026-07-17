#!/bin/bash

###############################################################
# MOTD/Login Quick Information script                         #
# This script pulls information from a variety of sources     #
# in a Linux system, and aggregates it into a small table     #
# that is displayed upon terminal login to the system.        #
#                                                             #
#           Written by Alan "pyr0ball" Weinstock              #
#           Enhanced for multi-distro compatibility           #
###############################################################

quickinfo_version=4.1.2
prbl_functons_req_ver=2.1.0

# Source PRbL Functions locally or retrieve from online
if [ -f $prbl_functions ] ; then
    source $prbl_functions
else
    if [ -f ${rundir}/functions ] ; then
        source ${rundir}/functions
    else
        # Iterate through get commands and fall back on next if unavailable
        if command -v curl >/dev/null 2>&1; then
            source <(curl -ks 'https://raw.githubusercontent.com/pyr0ball/PRbL/main/functions')
        elif command -v wget >/dev/null 2>&1; then
            source <(wget -qO- 'https://raw.githubusercontent.com/pyr0ball/PRbL/main/functions')
        elif command -v fetch >/dev/null 2>&1; then
            source <(fetch -qo- 'https://raw.githubusercontent.com/pyr0ball/PRbL/main/functions')
        else
            echo "Error: curl, wget, and fetch commands are not available. Please install one to retrieve PRbL functions."
            exit 1
        fi
    fi
fi

# Locate script information
scriptname="${BASH_SOURCE[0]##*/}"
rundir="${BASH_SOURCE[0]%/*}"

# Degree symbol used in temperature readouts. PRbL/functions sets
# unicode_supported when sourced; fall back to a bare "C" (no degree sign)
# on terminals/locales without Unicode support.
deg_symbol='°'
[[ "$unicode_supported" == true ]] || deg_symbol=''

########################################
# Default quickinfo bashrc Preferences #
########################################

# Disable run on non-interactive sessions (set true to disable)
interactive_only=false

# Network Adapter Preferences
# set false to hide network adapters without valid IP's
show_disconnected=true

# Ignored network adapter names (regex match)
# separate adapter names with '\|' ex. "lo\|tun0"
filtered_adapters="lo"

# Disks
allowed_disk_prefixes=(
  "sd"
  "md"
  "mapper"
  "nvme"
  "mmcblk"
  "root"
  "vd"
  "xvd"
)

disallowed_disk_prefixes=(
  "boot"
  "snap"
  "loop"
)

# Settings for additional information display
show_gpu_info=true
show_container_info=true
show_service_status=true
show_security_info=true
show_smart_status=false # Requires root privileges or sudo config
show_top_processes=true
show_power_info=true # Enable power monitoring (requires appropriate hardware/sensors)
show_power_details=false

# Services to check (space separated list)
critical_services="sshd nginx apache2 mysqld mariadb docker containerd kubelet cron"

#######################################################
# Do not change these unless you know what you're doing

allowed_disk_prefixes_string=""
disallowed_disk_prefixes_string=""

# Build the allowed disk prefixes pattern
for prefix in "${allowed_disk_prefixes[@]}"; do
  if [ -z "$allowed_disk_prefixes_string" ]; then
    allowed_disk_prefixes_string="$prefix"
  else
    allowed_disk_prefixes_string+="\\|$prefix"
  fi
done

# Build the disallowed disk prefixes pattern
for prefix in "${disallowed_disk_prefixes[@]}"; do
  if [ -z "$disallowed_disk_prefixes_string" ]; then
    disallowed_disk_prefixes_string="$prefix"
  else
    disallowed_disk_prefixes_string+="\\|$prefix"
  fi
done

# check PRbL functions version
if command -v vercomp >/dev/null 2>&1; then
  if [[ $(vercomp $functionsrev $prbl_functons_req_ver) == 2 ]] ; then
    warn "PRbL functions installed are lower than recommended ($prbl_functons_req_ver)"
    warn "Some features may not work as expected"
  fi
fi

################################
# Enhanced OS Detection Function
################################

detect_os() {
  # Initialize OS info variables
  OS="Unknown"
  VER="Unknown"
  ID="Unknown"
  
  # Method 1: lsb_release
  if command -v lsb_release >/dev/null 2>&1; then
    OS=$(lsb_release -si)
    VER=$(lsb_release -sr)
    ID=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
    return
  fi
  
  # Method 2: /etc/os-release
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
    ID=${ID:-$NAME}
    ID=$(echo $ID | tr '[:upper:]' '[:lower:]')
    return
  fi
  
  # Method 3: /etc/lsb-release
  if [ -f /etc/lsb-release ]; then
    . /etc/lsb-release
    OS=$DISTRIB_ID
    VER=$DISTRIB_RELEASE
    ID=$(echo $DISTRIB_ID | tr '[:upper:]' '[:lower:]')
    return
  fi
  
  # Method 4: /etc/{system}-release files
  for release_file in /etc/*-release; do
    if [ -f "$release_file" ] && [ "$release_file" != "/etc/os-release" ] && [ "$release_file" != "/etc/lsb-release" ]; then
      OS=$(head -n1 "$release_file" | cut -d' ' -f1)
      VER=$(head -n1 "$release_file" | grep -o -E '[0-9]+\.[0-9]+' | head -n1)
      ID=$(echo $OS | tr '[:upper:]' '[:lower:]')
      return
    fi
  done
  
  # Method 5: Fallback to uname
  OS=$(uname -s)
  VER=$(uname -r)
  ID=$(echo $OS | tr '[:upper:]' '[:lower:]')
}

################################
# Package Manager Detection
################################

detect_package_manager() {
  package_manager="unknown"
  update_cmd=""
  update_check_cmd=""
  
  if command -v apt >/dev/null 2>&1 || command -v apt-get >/dev/null 2>&1; then
    package_manager="apt"
    update_cmd="apt update && apt upgrade"
    if [ -f /usr/lib/update-notifier/apt-check ]; then
      update_check_cmd="/usr/lib/update-notifier/apt-check --human-readable"
    else
      update_check_cmd="apt list --upgradable 2>/dev/null | grep -c ^"
    fi
  elif command -v dnf >/dev/null 2>&1; then
    package_manager="dnf"
    update_cmd="dnf upgrade"
    update_check_cmd="dnf check-update --quiet | grep -v \"^$\" | wc -l"
  elif command -v yum >/dev/null 2>&1; then
    package_manager="yum"
    update_cmd="yum update"
    update_check_cmd="yum check-update --quiet | grep -v \"^$\" | wc -l"
  elif command -v pacman >/dev/null 2>&1; then
    package_manager="pacman"
    update_cmd="pacman -Syu"
    update_check_cmd="pacman -Qu | wc -l"
  elif command -v zypper >/dev/null 2>&1; then
    package_manager="zypper"
    update_cmd="zypper update"
    update_check_cmd="zypper list-updates | grep -c \"^v \""
  elif command -v apk >/dev/null 2>&1; then
    package_manager="apk"
    update_cmd="apk update && apk upgrade"
    update_check_cmd="apk version -v | grep -c upgradable"
  fi
}

################################
# Check for Updates
################################

check_for_updates() {
  packages_available=0
  security_updates=0
  need_updates=false
  
  case $package_manager in
    apt)
      if [ -f /usr/lib/update-notifier/apt-check ]; then
        # Capture both stdout and stderr, and handle malformed output
        apt_check_output=$(/usr/lib/update-notifier/apt-check 2>&1)
        
        # Validate that we have a proper semicolon-separated output
        if [[ "$apt_check_output" == *";"* ]]; then
          packages_available=$(echo "$apt_check_output" | cut -d';' -f1)
          security_updates=$(echo "$apt_check_output" | cut -d';' -f2)
          
          # Validate that packages_available is a valid number
          if [[ "$packages_available" =~ ^[0-9]+$ ]]; then
            if [ $packages_available -gt 0 ]; then
              packages="${packages_available} updates can be installed"
              need_updates=true
            else
              packages="0 updates available"
            fi
          else
            packages="Error parsing update count"
          fi
          
          # Validate that security_updates is a valid number
          if [[ "$security_updates" =~ ^[0-9]+$ ]]; then
            if [ $security_updates -gt 0 ]; then
              supdates="${security_updates} security updates"
              need_updates=true
            else
              supdates="0 security updates"
            fi
          else
            supdates="Error parsing security updates"
          fi
        else
          packages="Invalid update-notifier output"
        fi
      else
        # If apt-check isn't available, try an alternative method
        if command -v apt >/dev/null 2>&1; then
          # This method requires root/sudo, will be empty if not available
          # FIX: Properly capture and process the apt list output
          apt_output=$(apt list --upgradable 2>/dev/null)
          if [ $? -eq 0 ]; then
            # Only count lines that actually contain "upgradable" to avoid parsing errors
            packages_count=$(echo "$apt_output" | grep -c "upgradable" || echo "0")
            
            # Ensure we have a clean numeric value
            if [[ "$packages_count" =~ ^[0-9]+$ ]]; then
              packages_available=$packages_count
              
              if [ $packages_available -gt 0 ]; then
                packages="${packages_available} updates can be installed"
                need_updates=true
              else
                packages="0 updates available"
              fi
            else
              packages="Error checking updates"
            fi
          else
            packages="Need privileges to check updates"
          fi
        else
          packages="apt not available"
        fi
      fi
      ;;
      
    dnf|yum)
      # Check if we can run as non-root
      if timeout 5 $package_manager check-update -q &>/dev/null; then
        # Capture the output in a variable and ensure it's a valid number
        check_output=$($update_check_cmd)
        if [[ "$check_output" =~ ^[0-9]+$ ]]; then
          packages_available=$check_output
          
          if [ $packages_available -gt 0 ]; then
            packages="${packages_available} updates can be installed"
            need_updates=true
          else
            packages="0 updates available"
          fi
        else
          packages="Error checking updates"
        fi
      else
        packages="Need root to check updates"
      fi
      ;;
      
    pacman)
      if pacman -Qu &>/dev/null; then
        # Ensure we get a clean numeric value
        check_output=$(pacman -Qu | wc -l)
        if [[ "$check_output" =~ ^[0-9]+$ ]]; then
          packages_available=$check_output
          
          if [ $packages_available -gt 0 ]; then
            packages="${packages_available} updates can be installed"
            need_updates=true
          else
            packages="0 updates available"
          fi
        else
          packages="Error checking updates"
        fi
      else
        packages="Need to run 'pacman -Sy' to check updates"
      fi
      ;;
      
    zypper)
      if timeout 5 zypper list-updates &>/dev/null; then
        # Ensure we get a clean numeric value
        check_output=$(zypper list-updates | grep '^v ' | wc -l)
        if [[ "$check_output" =~ ^[0-9]+$ ]]; then
          packages_available=$check_output
          
          if [ $packages_available -gt 0 ]; then
            packages="${packages_available} updates can be installed"
            need_updates=true
          else
            packages="0 updates available"
          fi
        else
          packages="Error checking updates"
        fi
      else
        packages="Need root to check updates"
      fi
      ;;
      
    apk)
      if timeout 5 apk version -v &>/dev/null; then
        # Ensure we get a clean numeric value
        check_output=$(apk version -v | grep -c upgradable)
        if [[ "$check_output" =~ ^[0-9]+$ ]]; then
          packages_available=$check_output
          
          if [ $packages_available -gt 0 ]; then
            packages="${packages_available} updates can be installed"
            need_updates=true
          else
            packages="0 updates available"
          fi
        else
          packages="Error checking updates"
        fi
      else
        packages="Need root to check updates"
      fi
      ;;
      
    *)
      packages="Unknown package manager"
      ;;
  esac
  
  # Check for release upgrade
  release_upgrade=""
  if [ -x /usr/lib/ubuntu-release-upgrader/release-upgrade-motd ]; then
    if [ -f /var/lib/ubuntu-release-upgrader/release-upgrade-available ]; then
      release_upgrade="$(cat /var/lib/ubuntu-release-upgrader/release-upgrade-available)"
      need_updates=true
    fi
  fi
}

################################
# CPU Temperature
################################

get_cpu_temp() {
  cputemp="N/A"
  
  # Method 1: lm-sensors
  if command -v sensors >/dev/null 2>&1; then
    temp=$(LC_ALL=C sensors | grep -m 1 -E 'Core 0|CPU Temp|Tdie' | grep -o -E '[0-9]+\.[0-9]+' | head -n1)
    if [ ! -z "$temp" ]; then
      cputemp=$(printf "%.0f" $temp)
    fi
  fi
  
  # Method 2: /sys/class/thermal
  if [ "$cputemp" = "N/A" ] && [ -d /sys/class/thermal ]; then
    for zone in /sys/class/thermal/thermal_zone*/temp; do
      if [ -f "$zone" ]; then
        temp=$(cat "$zone")
        if [ $temp -gt 0 ]; then
          # Convert millidegrees to degrees
          cputemp=$(( temp / 1000 ))
          break
        fi
      fi
    done
  fi
  
  # Method 3: Raspberry Pi specific
  if [ "$cputemp" = "N/A" ] && [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    temp=$(cat /sys/class/thermal/thermal_zone0/temp)
    cputemp=$(( temp / 1000 ))
  fi
  
  # Add color warning if temperature is high
  if [[ "$cputemp" != "N/A" ]]; then
    if [[ "$cputemp" -gt "65" ]]; then
      cputemp="${ong}${blk}${cputemp}${deg_symbol}C${dfl}"
    else
      cputemp="${cputemp}${deg_symbol}C"
    fi
  fi
}

################################
# GPU Information
################################

get_gpu_info() {
  gpu_info="N/A"
  gpu_temp="N/A"
  gpu_util="N/A"
  
  # Check for NVIDIA GPU with nvidia-smi
  if command -v nvidia-smi >/dev/null 2>&1; then
    gpu_info=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1 | cut -c -30)
    gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader | head -n1)
    gpu_util=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader | head -n1 | cut -d' ' -f1)
    
    # Add color to GPU temperature
    if [[ "$gpu_temp" != "N/A" ]]; then
      if [[ "$gpu_temp" -gt "70" ]]; then
        gpu_temp="${ong}${blk}${gpu_temp}${deg_symbol}C${dfl}"
      else
        gpu_temp="${gpu_temp}${deg_symbol}C"
      fi
    fi
    
    have_gpu=true
    return
  fi
  
  # Check for AMD GPU with rocm-smi
  if command -v rocm-smi >/dev/null 2>&1; then
    gpu_info=$(rocm-smi --showproductname | grep -v "===" | head -n1 | awk '{print $2}' | cut -c -30)
    gpu_temp=$(rocm-smi --showtemp | grep -v "===" | head -n1 | awk '{print $2}')
    
    # Add color to GPU temperature
    if [[ "$gpu_temp" != "N/A" ]]; then
      if [[ "$gpu_temp" -gt "70" ]]; then
        gpu_temp="${ong}${blk}${gpu_temp}${deg_symbol}C${dfl}"
      else
        gpu_temp="${gpu_temp}${deg_symbol}C"
      fi
    fi
    
    have_gpu=true
    return
  fi
  
  # Basic GPU detection through lspci
  if command -v lspci >/dev/null 2>&1; then
    gpu_info=$(lspci | grep -i 'vga\|3d\|display' | head -n1 | cut -d: -f3 | cut -c -30)
    if [ ! -z "$gpu_info" ]; then
      have_gpu=true
      return
    fi
  fi
  
  have_gpu=false
}

################################
# Get Container/VM Information
################################

get_container_info() {
  container_type="N/A"
  container_stats="N/A"
  in_container=false
  
  # Check if running in Docker
  if [ -f /.dockerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null; then
    container_type="Docker"
    in_container=true
  fi
  
  # Check if running in LXC/LXD
  if grep -q lxc /proc/1/cgroup 2>/dev/null; then
    container_type="LXC"
    in_container=true
  fi
  
  # Check if running in Kubernetes
  if [ -f /var/run/secrets/kubernetes.io/serviceaccount/namespace ]; then
    container_type="Kubernetes Pod"
    in_container=true
  fi
  
  # Check for systemd-nspawn
  if [ -d /run/systemd/nspawn ]; then
    container_type="systemd-nspawn"
    in_container=true
  fi
  
  # Check for VM
  if [ "$in_container" = false ]; then
    if command -v systemd-detect-virt >/dev/null 2>&1; then
      virt=$(systemd-detect-virt)
      if [ "$virt" != "none" ]; then
        container_type="VM ($virt)"
        in_container=true
      fi
    elif [ -e /proc/cpuinfo ]; then
      if grep -q "hypervisor" /proc/cpuinfo; then
        container_type="VM (unknown)"
        in_container=true
      fi
    fi
  fi
  
  # Get Docker container stats if Docker is installed
  if command -v docker >/dev/null 2>&1 && [ "$in_container" = false ]; then
    container_count=$(docker ps -q 2>/dev/null | wc -l || echo "0")
    if [ "$container_count" -gt 0 ]; then
      container_stats="$container_count running Docker containers"
      have_containers=true
    else
      container_stats="No running containers"
      have_containers=false
    fi
  fi
  
  # Get LXC container stats if LXC is installed
  # if command -v lxc >/dev/null 2>&1 && [ "$in_container" = false ]; then
  #   container_count=$(lxc list --format csv -c s | grep -c RUNNING 2>/dev/null || echo "0")
  #   if [ "$container_count" -gt 0 ]; then
  #     container_stats="$container_stats, $container_count running LXC containers"
  #     have_containers=true
  #   fi
  # fi
}

# Get public IP address using multiple fallbacks
get_wan_ip() {
  wan_ip="Unavailable"
  
  # Try multiple services with a timeout to avoid hanging
  if command -v curl >/dev/null 2>&1; then
    wan_ip=$(timeout 2 curl -s ifconfig.me 2>/dev/null || \
             timeout 2 curl -s icanhazip.com 2>/dev/null || \
             timeout 2 curl -s ipecho.net/plain 2>/dev/null || \
             timeout 2 curl -s api.ipify.org 2>/dev/null || \
             echo "Unavailable")
  elif command -v wget >/dev/null 2>&1; then
    wan_ip=$(timeout 2 wget -qO- ifconfig.me 2>/dev/null || \
             timeout 2 wget -qO- icanhazip.com 2>/dev/null || \
             timeout 2 wget -qO- ipecho.net/plain 2>/dev/null || \
             timeout 2 wget -qO- api.ipify.org 2>/dev/null || \
             echo "Unavailable")
  elif command -v fetch >/dev/null 2>&1; then
    wan_ip=$(timeout 2 fetch -qo- ifconfig.me 2>/dev/null || \
             timeout 2 fetch -qo- icanhazip.com 2>/dev/null || \
             timeout 2 fetch -qo- ipecho.net/plain 2>/dev/null || \
             timeout 2 fetch -qo- api.ipify.org 2>/dev/null || \
             echo "Unavailable")
  fi
  
  echo "$wan_ip"
}

################################
# Get Service Status
################################

get_service_status() {
  services_down=()
  
  if command -v systemctl >/dev/null 2>&1; then
    for service in $critical_services; do
      if systemctl is-active --quiet $service 2>/dev/null; then
        # Service is running, do nothing
        :
      elif systemctl is-enabled --quiet $service 2>/dev/null; then
        # Service is enabled but not running
        services_down+=("$service")
      fi
    done
  elif command -v service >/dev/null 2>&1; then
    for service in $critical_services; do
      if service $service status &>/dev/null; then
        # Service is running, do nothing
        :
      else
        # Check if service exists but is not running
        if [ -f "/etc/init.d/$service" ]; then
          services_down+=("$service")
        fi
      fi
    done
  fi
  
  if [ ${#services_down[@]} -gt 0 ]; then
    service_status="${lrd}Services down: ${services_down[*]}${dfl}"
    have_service_issues=true
  else
    service_status="${grn}All monitored services running${dfl}"
    have_service_issues=false
  fi
}

################################
# Get Security Information
################################

get_security_info() {
  failed_logins=0
  last_login="N/A"
  ssh_sessions=0
  
  # Get failed login attempts
  if command -v journalctl >/dev/null 2>&1; then
    failed_logins=$(journalctl -u sshd --since yesterday | grep -c "Failed password")
  elif [ -f /var/log/auth.log ]; then
    failed_logins=$(grep -c "Failed password" /var/log/auth.log)
  fi
  
  # Get last successful login
  if command -v last >/dev/null 2>&1; then
    last_user=$(who am i | awk '{print $1}')
    if [ ! -z "$last_user" ]; then
      last_login=$(last -n 2 $last_user | head -n 1 | awk '{print $4" "$5" "$6" "$7}')
    fi
  fi
  
  # Get current SSH sessions
  if command -v who >/dev/null 2>&1; then
    ssh_sessions=$(who | grep -c "pts")
  fi
  
  # Get firewall status without requiring root privileges
  if command -v ufw >/dev/null 2>&1; then
    # Check if ufw is loaded in kernel modules - doesn't require root
    if lsmod | grep -q "^ufw"; then
      # Check if there are any ufw rules by looking at iptables (if readable)
      if [ -r /etc/ufw/user.rules ]; then
        ufw_rules=$(grep -c "^-A" /etc/ufw/user.rules)
        if [ $ufw_rules -gt 0 ]; then
          firewall_status="UFW: likely active with $ufw_rules rules"
        else
          firewall_status="UFW: likely inactive (no rules found)"
        fi
      else
        # Check status of ufw service without sudo
        if systemctl is-active --quiet ufw 2>/dev/null; then
          firewall_status="UFW: service running"
        else
          firewall_status="UFW: service not running"
        fi
      fi
    else
      firewall_status="UFW: module not loaded (inactive)"
    fi
  elif command -v firewall-cmd >/dev/null 2>&1; then
    # For firewalld, check if the service is running
    if systemctl is-active --quiet firewalld 2>/dev/null; then
      firewall_status="firewalld: service running"
    else
      firewall_status="firewalld: service not running"
    fi
  elif command -v iptables >/dev/null 2>&1; then
    # Check for iptables rules (non-root might not see all)
    if iptables -L -n 2>/dev/null | grep -q "REJECT\|DROP"; then
      firewall_status="iptables: active"
    elif [ -r /etc/iptables/rules.v4 ] || [ -r /etc/sysconfig/iptables ]; then
      # Check for saved rules files
      firewall_status="iptables: likely active (rules file exists)"
    elif systemctl is-active --quiet iptables 2>/dev/null; then
      firewall_status="iptables: service running"
    else
      firewall_status="iptables: status unknown"
    fi
  else
    firewall_status="No firewall detected"
  fi
}

################################
# Get SMART Disk Status
################################

get_smart_status() {
  smart_alerts=()
  
  if command -v smartctl >/dev/null 2>&1; then
    for disk in $(lsblk -d -o name | grep -E "^($allowed_disk_prefixes_string)" | grep -v -E "^($disallowed_disk_prefixes_string)"); do
      # Try to run smartctl without sudo first
      smart_status=$(smartctl -H /dev/$disk 2>/dev/null)
      if [ $? -ne 0 ]; then
        # If failed, try with sudo if available (won't work without password prompt in most cases)
        if command -v sudo >/dev/null 2>&1; then
          smart_status=$(sudo -n smartctl -H /dev/$disk 2>/dev/null || echo "Permission denied")
        else
          smart_status="Permission denied"
        fi
      fi
      
      if echo "$smart_status" | grep -q "FAILED"; then
        smart_alerts+=("${lrd}/dev/$disk FAILED${dfl}")
      elif echo "$smart_status" | grep -q "Permission denied"; then
        continue
      fi
    done
  fi
  
  if [ ${#smart_alerts[@]} -gt 0 ]; then
    smart_status="${lrd}SMART Alerts: ${smart_alerts[*]}${dfl}"
    have_smart_issues=true
  else
    smart_status="${grn}No SMART alerts detected${dfl}"
    have_smart_issues=false
  fi
}

################################
# Get Top Processes
################################

get_top_processes() {
  if command -v ps >/dev/null 2>&1; then
    # Get top 3 CPU processes
    top_cpu=$(ps -eo pcpu,pid,user,args --sort=-pcpu | head -n 4 | tail -n 3 | awk '{printf "%-5s %-8s %-15.15s\n", $1"%", $3, $4}')
    
    # Get top 3 memory processes
    top_mem=$(ps -eo pmem,pid,user,args --sort=-pmem | head -n 4 | tail -n 3 | awk '{printf "%-5s %-8s %-15.15s\n", $1"%", $3, $4}')
  fi
}

################################
# Main Logic
################################

# Run detection functions
detect_os
detect_package_manager
check_for_updates
get_cpu_temp

# Get network information
location=$(uname -a | awk '{print $2}')
image_version=$(uname -r)
software_version="$OS $VER"
mem_usage=$(LC_ALL=C free -m | grep Mem | awk '{print $3"M/"$2"M"}')

# Get swap usage
swap_usage=$(LC_ALL=C free -m | grep Swap | awk '{if ($2 > 0) print $3"M/"$2"M"; else print "None"}')

# Get number of CPUs and load averages
num_cpus=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1)
load_check=$(LC_ALL=C uptime | sed -r 's|.*load average: ([\.0-9]+), ([\.0-9]+), ([\.0-9]+)|\1 \2 \3|g')
load_averages=$(echo "$load_check $num_cpus" | awk '{printf "5min: %.0f%% ", $1/$4*100} {printf "10min: %.0f%% ", $2/$4*100} {printf "15min: %.0f%%", $3/$4*100}' ORS=' ')

# Calculate CPU utilization
# Read /proc/stat file (for first datapoint)
read cpu user nice system idle iowait irq softirq steal guest < /proc/stat
# compute active and total utilizations
cpu_active_prev=$((user+system+nice+softirq+steal))
cpu_total_prev=$((user+system+nice+softirq+steal+idle+iowait))
sleep 0.3
# Read /proc/stat file (for second datapoint)
read cpu user nice system idle iowait irq softirq steal guest < /proc/stat
# compute active and total utilizations
cpu_active_cur=$((user+system+nice+softirq+steal))
cpu_total_cur=$((user+system+nice+softirq+steal+idle+iowait))
# compute CPU utilization (%)
cpu_util=$((100*( cpu_active_cur-cpu_active_prev ) / (cpu_total_cur-cpu_total_prev) ))

# Get uptime in human-readable format
# NOTE: this token-position parsing is locale/format-fragile (procps wording
# and column count shift across distros); LC_ALL=C at least stabilizes the
# wording. A /proc/uptime-based rewrite would be more robust; tracked as follow-up.
uptime_raw="$(LC_ALL=C uptime)"
if [[ "$(grep -iq day <<< "$uptime_raw" ; echo $?)" == "0" ]] ; then
    # first logic gate, if the system has been online for at least a day
    if [[ "$(grep -iq min <<< "$uptime_raw" ; echo $?)" == "0" ]] ; then
        # nested logic gate. If the system has been online for more than a day
        # but less than a day and an hour, the tokens shift and requires alternate parsing
        s_uptime=$(awk '{print $3 " " $4 " " $5 " Minutes"}' <<< "$uptime_raw")
    else # gate for if the system has been online longer than one day and one hour
        s_uptime=$(awk '{print $3 " " $4 " " $5 " Hours"}' <<< "$uptime_raw")
    fi
else # logic gate for if the system has been online less than a day but more than an hour
    if [[ "$(grep -iq min <<< "$uptime_raw" ; echo $?)" == "1" ]] ; then
        s_uptime=$(awk '{print $3 " Hours  "}' <<< "$uptime_raw")
    else
        s_uptime=$(awk '{print $3 " Minutes    "}' <<< "$uptime_raw")
    fi
fi

# Get additional information if enabled
if [ "$show_gpu_info" = true ]; then
  get_gpu_info
fi

if [ "$show_container_info" = true ]; then
  get_container_info
fi

if [ "$show_service_status" = true ]; then
  get_service_status
fi

if [ "$show_security_info" = true ]; then
  get_security_info
fi

if [ "$show_smart_status" = true ]; then
  get_smart_status
fi

if [ "$show_top_processes" = true ]; then
  get_top_processes
fi

# Check for fsck message
if [ -x /usr/lib/update-notifier/update-motd-fsck-at-reboot ]; then
    fsck_needed="$(exec /usr/lib/update-notifier/update-motd-fsck-at-reboot)"
fi

# Check if reboot required by updates
reboot_required=""
if [ -f /var/run/reboot-required ]; then
    reboot_required=$(cat /var/run/reboot-required)
fi

# Network display and filtering
declare -a adapters=()
declare -a ips=()
declare -a macs=()
declare -a ifups=()
for device in $(ls /sys/class/net/ 2>/dev/null | grep -v "$filtered_adapters"); do
  adapters+=($device)
  _ip=$(ip -o -f inet addr show $device 2>/dev/null | awk '{print $4}' | cut -d/ -f 1 | head -n 1)
  if valid-ip $_ip; then
    ips+=("$_ip")
    ifups+=("up")
  else
    ips+=("${red}disconnected${dfl}")
    ifups+=("down")
  fi
  if [ -f /sys/class/net/${device}/address ]; then
    macs+=("$(cat /sys/class/net/${device}/address)")
  else
    macs+=("unknown")
  fi
done

# Run as a background process to avoid hanging the login
wan_ip=$(get_wan_ip &)

# Disk array setup
declare -a logicals=()
declare -a mounts=()
declare -a usages=()
declare -a freespaces=()
diskinfo=$(/bin/df -h | grep "$allowed_disk_prefixes_string" | grep -v "$disallowed_disk_prefixes_string")
logicals=($(echo "$diskinfo" | awk '{print $1}'))
mounts=($(echo "$diskinfo" | awk '{print $6}'))
usages=($(echo "$diskinfo" | awk '{print $5}'))
freespaces=($(echo "$diskinfo" | awk '{print $4}'))

# Add color to disk usage if more than 90%
for i in "${!usages[@]}"; do
  usage="${usages[$i]}"
  percentage="${usage%\%}"
  if [[ "$percentage" -gt "90" ]]; then
    usages[$i]="${lrd}${usage}${dfl}"
  elif [[ "$percentage" -gt "75" ]]; then
    usages[$i]="${ong}${usage}${dfl}"
  fi
done

###############################################
# Display the formatted information
###############################################

boxtop
boxline ""
boxline "${bld}${unl}System Information:${dfl}  ${grn}${unl}$location${dfl}"
boxline "	${bld}OS:${dfl} ${ong}${software_version}${dfl} | ${bld}Kernel:${dfl} ${pur}${image_version}${dfl}"
boxline "	${bld}Uptime:${dfl} ${s_uptime}"

# Container information
if [ "$show_container_info" = true ] && [[ "$in_container" = true || "$have_containers" = true ]]; then
  boxline ""
  boxline "${bld}${unl}Container/VM Information:${dfl}"
  if [ "$in_container" = true ]; then
    boxline "	${bld}Running in:${dfl} ${ylw}${container_type}${dfl}"
  fi
  if [ "$have_containers" = true ]; then
    boxline "	${bld}Container Status:${dfl} ${container_stats}"
  fi
fi

# Network information
boxline ""
boxline "${bld}${unl}Network Information:${dfl}"
boxline "	|${unl}Interface       IP Address           MAC Address${dfl}"
boxline "	|-------------------------------------------------------"

# Echo out network arrays with consistent spacing
for ((i=0; i<"${#adapters[@]}"; i++ )); do
  # Skip displaying disconnected interfaces if flag is false
  if [[ $show_disconnected != true ]] && [[ ${ifups[$i]} != "up" ]]; then
    continue
  fi
  
  # Extract plain text without color codes for formatting
  ip_plain=$(echo "${ips[$i]}" | sed 's/\x1b\[[0-9;]*m//g')
  
  # Format columns with fixed widths, adding colors as requested
  interface_col=$(printf "${cyn}%-15s${dfl}" "${adapters[$i]}")
  
  # Handle IP color - yellow for connected, keep existing red for disconnected
  if [[ ${ifups[$i]} == "up" ]]; then
    # For connected IPs, use yellow instead of cyan
    ip_col=$(printf "${ylw}%-19s${dfl}" "$ip_plain")
  else
    # For disconnected IPs, keep the red color but maintain spacing
    ip_col="${ips[$i]}$(printf '%*s' $((19 - ${#ip_plain})) '')"
  fi
  
  # Add light blue for MAC addresses
  mac_col=$(printf "${lbl}%s${dfl}" "${macs[$i]}")
  
  # Combine the formatted columns
  formatted_line="|${interface_col}${ip_col}${mac_col}"
  boxline "	$formatted_line"
done

# Display WAN IP separately
boxline "	|-------------------------------------------------------"
boxline "	${bld}WAN IP:${dfl}	${grn}${wan_ip}${dfl}"

# System status
boxline ""
boxline "${bld}${unl}System Resources:${dfl}"
boxline "	${bld}CPU Load:${dfl} ${load_averages}"
boxline "	${bld}CPU Temp:${dfl} ${lbl}${cputemp}${dfl} | ${bld}Utilization:${dfl} ${lrd}${cpu_util}%${dfl}"

# GPU information if available
if [ "$show_gpu_info" = true ] && [ "$have_gpu" = true ]; then
  boxline "	${bld}GPU:${dfl} ${ylw}${gpu_info}${dfl}"
  if [ "$gpu_temp" != "N/A" ]; then
    boxline "	${bld}GPU Temp:${dfl} ${lbl}${gpu_temp}${dfl} | ${bld}Utilization:${dfl} ${lrd}${gpu_util}%${dfl}"
  fi
fi

# Memory usage
boxline "	${bld}Memory:${dfl} ${mem_usage} | ${bld}Swap:${dfl} ${swap_usage}"

# Storage info
boxline "	${bld}${unl}Disk Info:${dfl}"
boxline "	|${unl}Usage    Free        Mount         Volumes${dfl}"
boxline "	|-----------------------------------------------"

# Loop through each disk and display info with precise column widths
for ((i=0; i<"${#logicals[@]}"; i++)); do
  # Extract the usage text without color codes for formatting
  usage_plain=$(echo "${usages[$i]}" | sed 's/\x1b\[[0-9;]*m//g')
  
  # Format the columns
  usage_col=$(printf "%-8s" "$usage_plain")
  free_col=$(printf "%-12s" "${freespaces[$i]}")
  mount_col=$(printf "%-13s" "${mounts[$i]}")
  volume_col="${logicals[$i]}"
  
  # Replace the plain text with the colored version, maintaining the same length
  usage_col="${usages[$i]}$(printf '%*s' $((8 - ${#usage_plain})) '')"
  
  # Combine the formatted columns
  formatted_line="|${usage_col}${free_col}${mount_col}${volume_col}"
  boxline "	$formatted_line"
done

# SMART status if enabled and issues detected
if [ "$show_smart_status" = true ] && [ "$have_smart_issues" = true ]; then
  boxline ""
  boxline "${bld}${unl}Disk Health:${dfl}"
  boxline "	${smart_status}"
fi

# Service status if enabled and issues detected
if [ "$show_service_status" = true ] && [ "$have_service_issues" = true ]; then
  boxline ""
  boxline "${bld}${unl}Service Status:${dfl}"
  boxline "	${service_status}"
fi

# Security information if enabled
if [ "$show_security_info" = true ]; then
  boxline ""
  boxline "${bld}${unl}Security Information:${dfl}"
  boxline "	${bld}Failed logins (24h):${dfl} ${failed_logins}"
  boxline "	${bld}Active SSH sessions:${dfl} ${ssh_sessions}"
  if [ "$last_login" != "N/A" ]; then
    boxline "	${bld}Last login:${dfl} ${last_login}"
  fi
  boxline "	${bld}Firewall:${dfl} ${firewall_status}"
fi

# Power information if enabled
if [ "$show_power_info" = true ]; then
  get_power_info
  if [[ "$system_power" != "N/A" || "$cpu_power" != "N/A" || "$gpu_power" != "N/A" || "$battery_power" != "N/A" ]]; then
    boxline ""
    boxline "${bld}${unl}Power Usage:${dfl}"
    
    if [[ "$system_power" != "N/A" ]]; then
      boxline "	${bld}System:${dfl} ${ong}${system_power}${dfl}"
    fi
    
    if [[ "$cpu_power" != "N/A" ]]; then
      boxline "	${bld}CPU:${dfl} ${lrd}${cpu_power}${dfl}"
    fi
    
    if [[ "$gpu_power" != "N/A" ]]; then
      boxline "	${bld}GPU:${dfl} ${lrd}${gpu_power}${dfl}"
    fi
    
    if [[ "$battery_power" != "N/A" ]]; then
      boxline "	${bld}Battery:${dfl} ${ylw}${battery_power}${dfl}"
    fi
    
    # Show detailed breakdown if requested
    if [[ "$show_power_details" == "true" && ${#power_sources[@]} -gt 0 ]]; then
      boxline "	${bld}${unl}Power Details:${dfl}"
      
      for ((i=0; i<${#power_sources[@]}; i++)); do
        boxline "	$(printf "%-25s %3d%s" "${power_sources[$i]}:" "${power_values[$i]}" "${power_units[$i]}")"
      done
    fi
  fi
fi

# Top processes if enabled
if [ "$show_top_processes" = true ]; then
  boxline ""
  boxline "${bld}${unl}Top CPU Processes:${dfl}"
  echo "$top_cpu" | while IFS= read -r line; do
    boxline "	$line"
  done
  
  boxline ""
  boxline "${bld}${unl}Top Memory Processes:${dfl}"
  echo "$top_mem" | while IFS= read -r line; do
    boxline "	$line"
  done
fi

# Update information if needed
if [[ "$need_updates" == "true" ]]; then
  boxline ""
  boxline "${bld}${unl}Updates:${dfl}"
  boxline "	${packages}"
  if [ ! -z "$supdates" ]; then
    boxline "	${supdates}"
  fi
  if [ ! -z "$release_upgrade" ]; then
    boxline "	${release_upgrade}"
  fi
fi

# System maintenance notifications
if [ ! -z "${fsck_needed}" ] || [ ! -z "${reboot_required}" ]; then
  boxline ""
  boxline "${bld}${unl}System Maintenance:${dfl}"
  boxline "	${fsck_needed} ${reboot_required}"
fi

boxline ""
boxbottom