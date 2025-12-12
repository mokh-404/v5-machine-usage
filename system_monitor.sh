#!/bin/bash

################################################################################
# System Monitoring Script - Arab Academy 12th Project
# Comprehensive System Monitoring Solution
# Works on WSL1 and Native Linux
################################################################################

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
REPORT_DIR="${SCRIPT_DIR}/reports"
DATA_DIR="${SCRIPT_DIR}/data"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/system_monitor.log"
CSV_FILE="${DATA_DIR}/metrics.csv"
HTML_REPORT="${REPORT_DIR}/report.html"

# Global metric storage (pipe-delimited format)
declare -A METRICS

################################################################################
# Logging Functions
################################################################################

log_message() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

log_error() {
    log_message "ERROR: $1"
}

log_warning() {
    log_message "WARNING: $1"
}

log_info() {
    log_message "INFO: $1"
}

################################################################################
# Error Handling
################################################################################

error_handler() {
    log_error "$1"
    exit 1
}

trap 'error_handler "Unexpected error occurred at line $LINENO"' ERR

################################################################################
# Setup Functions
################################################################################

setup_directories() {
    log_info "Setting up directory structure..."
    
    mkdir -p "$LOG_DIR" || error_handler "Failed to create logs directory"
    mkdir -p "$REPORT_DIR" || error_handler "Failed to create reports directory"
    mkdir -p "$DATA_DIR" || error_handler "Failed to create data directory"
    
    log_info "Directories created successfully"
}

display_header() {
    echo ""
    echo "================================================================================"
    echo "  Comprehensive System Monitoring Solution"
    echo "  Arab Academy 12th Project"
    echo "================================================================================"
    echo ""
    
    # Detect Environment (Local Check)
    if grep -qEi "(microsoft|wsl)" /proc/version 2>/dev/null; then
        local kernel_release=$(cat /proc/sys/kernel/osrelease 2>/dev/null || echo "")
        local wsl_ver_disp="WSL"
        
        if echo "$kernel_release" | grep -qi "WSL2\|microsoft.*WSL2"; then
            wsl_ver_disp="WSL2"
        elif echo "$kernel_release" | grep -qi "microsoft"; then
            wsl_ver_disp="WSL1"
        fi
        
        echo "  Environment: $wsl_ver_disp (Windows Subsystem for Linux)"
        
        if [ "$wsl_ver_disp" = "WSL2" ]; then
            echo ""
            echo "  ⚠ WARNING: WSL2 detected! Memory shown will be VM virtual memory, not Windows host memory."
            echo "  ⚠ For real Windows host memory, convert to WSL1: wsl --set-version <distro> 1"
            echo ""
        fi
    else
        echo "  Environment: Native Linux"
    fi
    
    echo "  Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "  Log File: $LOG_FILE"
    echo ""
    echo "================================================================================"
    echo ""
    
    log_info "Starting system monitoring..."
}

################################################################################
# Metric Collection Functions
################################################################################

# [1/10] CPU Performance
collect_cpu_metrics() {
    log_info "[1/10] Collecting CPU Metrics..."
    echo "[1/10] Collecting CPU Metrics..."
    
    # CPU Model
    local cpu_model=$(grep "^model name" /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^[ \t]*//')
    if [ -z "$cpu_model" ]; then
        cpu_model="Unknown"
    fi
    
    # CPU Cores
    local cpu_cores=$(grep -c "^processor" /proc/cpuinfo)
    if [ -z "$cpu_cores" ] || [ "$cpu_cores" -eq 0 ]; then
        cpu_cores=1
    fi
    
    # CPU Usage Calculation
    local cpu_usage=0
    if [ -r /proc/stat ]; then
        local cpu_line1=$(grep "^cpu " /proc/stat)
        sleep 1
        local cpu_line2=$(grep "^cpu " /proc/stat)
        
        local user1=$(echo "$cpu_line1" | awk '{print $2}')
        local nice1=$(echo "$cpu_line1" | awk '{print $3}')
        local system1=$(echo "$cpu_line1" | awk '{print $4}')
        local idle1=$(echo "$cpu_line1" | awk '{print $5}')
        
        local user2=$(echo "$cpu_line2" | awk '{print $2}')
        local nice2=$(echo "$cpu_line2" | awk '{print $3}')
        local system2=$(echo "$cpu_line2" | awk '{print $4}')
        local idle2=$(echo "$cpu_line2" | awk '{print $5}')
        
        local total1=$((user1 + nice1 + system1 + idle1))
        local total2=$((user2 + nice2 + system2 + idle2))
        
        local total_delta=$((total2 - total1))
        local idle_delta=$((idle2 - idle1))
        
        if [ "$total_delta" -gt 0 ]; then
            local used=$((total_delta - idle_delta))
            cpu_usage=$(echo "scale=2; ($used * 100) / $total_delta" | bc)
        fi
    fi
    
    # Load Average
    local load_avg=$(cat /proc/loadavg 2>/dev/null | awk '{print $1}')
    if [ -z "$load_avg" ]; then
        load_avg="0.00"
    fi
    
    # Store metrics
    METRICS[CPU_MODEL]="$cpu_model"
    METRICS[CPU_CORES]="$cpu_cores"
    METRICS[CPU_USAGE]="$cpu_usage"
    METRICS[LOAD_AVG]="$load_avg"
    
    # Display
    echo "  CPU Model:      $cpu_model"
    echo "  CPU Cores:      $cpu_cores"
    echo "  CPU Usage:      ${cpu_usage}%"
    echo "  Load Average:   $load_avg"
    echo ""
    
    log_info "CPU metrics collected: Model=$cpu_model, Cores=$cpu_cores, Usage=${cpu_usage}%, Load=$load_avg"
}

# [2/10] Memory Consumption
collect_memory_metrics() {
    log_info "[2/10] Collecting Memory Metrics..."
    echo "[2/10] Collecting Memory Metrics..."
    
    local mem_total_kb=$(grep "^MemTotal:" /proc/meminfo 2>/dev/null | awk '{print $2}')
    local mem_free_kb=$(grep "^MemFree:" /proc/meminfo 2>/dev/null | awk '{print $2}')
    local mem_available_kb=$(grep "^MemAvailable:" /proc/meminfo 2>/dev/null | awk '{print $2}')
    
    if [ -z "$mem_total_kb" ]; then
        mem_total_kb=0
    fi
    if [ -z "$mem_free_kb" ]; then
        mem_free_kb=0
    fi
    if [ -z "$mem_available_kb" ]; then
        mem_available_kb=$mem_free_kb
    fi
    
    # Convert to GB
    local mem_total_gb=$(echo "scale=2; $mem_total_kb / 1024 / 1024" | bc)
    local mem_free_gb=$(echo "scale=2; $mem_free_kb / 1024 / 1024" | bc)
    local mem_available_gb=$(echo "scale=2; $mem_available_kb / 1024 / 1024" | bc)
    local mem_used_gb=$(echo "scale=2; $mem_total_gb - $mem_free_gb" | bc)
    
    # Calculate percentage
    local mem_used_percent=0
    if [ "$(echo "$mem_total_gb > 0" | bc)" -eq 1 ]; then
        mem_used_percent=$(echo "scale=2; ($mem_used_gb * 100) / $mem_total_gb" | bc)
    fi
    
    # Check if we're on WSL2 or if memory seems limited (WSL1 should show real Windows host memory)
    local memory_warning=""
    # Check if we're on WSL (approximate check for warnings)
    if grep -qEi "(microsoft|wsl)" /proc/version 2>/dev/null; then
        local kernel_release=$(cat /proc/sys/kernel/osrelease 2>/dev/null || echo "")
        
        if echo "$kernel_release" | grep -qi "WSL2\|microsoft.*WSL2"; then
             memory_warning="WARNING: Detected WSL2 - Memory shown is VM virtual memory, not Windows host memory. Convert to WSL1 for real host memory access."
             log_warning "$memory_warning"
        elif [ "$(echo "$mem_total_gb < 8" | bc)" -eq 1 ]; then
            # Memory less than 8GB might indicate a limit or WSL2
            memory_warning="WARNING: Memory total (${mem_total_gb}GB) seems low. If on WSL1, check for .wslconfig memory limits. If on WSL2, convert to WSL1 for real host memory."
            log_warning "$memory_warning"
        fi
    fi
    
    # Store metrics
    METRICS[MEM_TOTAL]="$mem_total_gb"
    METRICS[MEM_FREE]="$mem_free_gb"
    METRICS[MEM_AVAILABLE]="$mem_available_gb"
    METRICS[MEM_USED]="$mem_used_gb"
    METRICS[MEM_USED_PERCENT]="$mem_used_percent"
    
    # Display
    echo "  Total Memory:   ${mem_total_gb} GB"
    echo "  Used Memory:    ${mem_used_gb} GB"
    echo "  Free Memory:    ${mem_free_gb} GB"
    echo "  Available:      ${mem_available_gb} GB"
    echo "  Usage:          ${mem_used_percent}%"
    
    if [ -n "$memory_warning" ]; then
        echo ""
        echo "  ⚠ $memory_warning"
    fi
    
    echo ""
    
    log_info "Memory metrics collected: Total=${mem_total_gb}GB, Used=${mem_used_gb}GB, Usage=${mem_used_percent}%"
}

# [3/10] Disk Usage
collect_disk_metrics() {
    log_info "[3/10] Collecting Disk Metrics..."
    echo "[3/10] Collecting Disk Metrics..."
    
    local disk_data_list=""
    local primary_disk_found=0
    
    # Header for console
    echo "  Filesystem      Mount Point     Total   Used    Avail   Usage"
    echo "  -------------------------------------------------------------"

    # Iterate over all relevant mounts
    # using df -h and properly handling lines
    while read -r line; do
        if [ -n "$line" ]; then
            local filesystem=$(echo "$line" | awk '{print $1}')
            local size=$(echo "$line" | awk '{print $2}')
            local used=$(echo "$line" | awk '{print $3}')
            local avail=$(echo "$line" | awk '{print $4}')
            local use_pct=$(echo "$line" | awk '{print $5}' | sed 's/%//')
            local mount=$(echo "$line" | awk '{print $6}')

            # Print to console
            printf "  %-15s %-15s %-7s %-7s %-7s %s%%\n" "$filesystem" "$mount" "$size" "$used" "$avail" "$use_pct"

            # Build list string (filesystem|mount|total|used|avail|percent)
            if [ -z "$disk_data_list" ]; then
                disk_data_list="${filesystem}|${mount}|${size}|${used}|${avail}|${use_pct}"
            else
                disk_data_list="${disk_data_list};${filesystem}|${mount}|${size}|${used}|${avail}|${use_pct}"
            fi

            # Keep 'C:' or '/' as primary metrics for CSV/Alerts
            if [ "$primary_disk_found" -eq 0 ]; then
                # Prefer /mnt/c or /
                if [[ "$mount" == "/mnt/c" ]] || [[ "$mount" == "/" ]]; then
                    METRICS[DISK_FILESYSTEM]="$filesystem"
                    METRICS[DISK_MOUNT]="$mount"
                    METRICS[DISK_TOTAL]="$size"
                    METRICS[DISK_USED]="$used"
                    METRICS[DISK_AVAILABLE]="$avail"
                    METRICS[DISK_USED_PERCENT]="$use_pct"
                    primary_disk_found=1
                fi
            fi
        fi
    done <<< "$(df -h | grep -E '^/|/mnt/' | grep -vE '^none|^tmpfs|^overlay')"

    # Fallback if no primary found (use first one)
    if [ "$primary_disk_found" -eq 0 ] && [ -n "$disk_data_list" ]; then
        IFS=';' read -ra FIRST_DISK <<< "$disk_data_list"
        IFS='|' read -ra F_DATA <<< "${FIRST_DISK[0]}"
        METRICS[DISK_FILESYSTEM]="${F_DATA[0]}"
        METRICS[DISK_MOUNT]="${F_DATA[1]}"
        METRICS[DISK_TOTAL]="${F_DATA[2]}"
        METRICS[DISK_USED]="${F_DATA[3]}"
        METRICS[DISK_AVAILABLE]="${F_DATA[4]}"
        METRICS[DISK_USED_PERCENT]="${F_DATA[5]}"
    fi

    METRICS[DISK_DATA_LIST]="$disk_data_list"
    
    echo ""
    log_info "Disk metrics collected for all drives"
}

# [4/10] SMART Status
collect_smart_status() {
    log_info "[4/10] Collecting SMART Status..."
    echo "[4/10] Collecting SMART Status..."
    
    local smart_status="Not Available"
    local smart_health="N/A"
    
    if command -v smartctl &>/dev/null; then
        local smart_output=$(smartctl -H /dev/sda 2>/dev/null)
        if [ $? -eq 0 ]; then
            smart_health=$(echo "$smart_output" | grep -i "SMART overall-health" | cut -d: -f2 | sed 's/^[ \t]*//')
            if [ -n "$smart_health" ]; then
                smart_status="Available"
            fi
        fi
    fi
    
    # Store metrics
    METRICS[SMART_STATUS]="$smart_status"
    METRICS[SMART_HEALTH]="$smart_health"
    
    # Display
    echo "  SMART Status:   $smart_status"
    echo "  Health:         $smart_health"
    echo ""
    
    log_info "SMART status collected: Status=$smart_status, Health=$smart_health"
}

# [5/10] Network Interface Statistics
collect_network_metrics() {
    log_info "[5/10] Collecting Network Metrics..."
    echo "[5/10] Collecting Network Metrics..."
    
    local network_data=""
    local interface_count=0
    
    for interface in /sys/class/net/*; do
        local iface_name=$(basename "$interface")
        
        # Skip loopback
        if [ "$iface_name" = "lo" ]; then
            continue
        fi
        
        local rx_bytes_file="${interface}/statistics/rx_bytes"
        local tx_bytes_file="${interface}/statistics/tx_bytes"
        local rx_packets_file="${interface}/statistics/rx_packets"
        local tx_packets_file="${interface}/statistics/tx_packets"
        
        if [ -r "$rx_bytes_file" ] && [ -r "$tx_bytes_file" ]; then
            local rx_bytes=$(cat "$rx_bytes_file" 2>/dev/null || echo "0")
            local tx_bytes=$(cat "$tx_bytes_file" 2>/dev/null || echo "0")
            local rx_packets=$(cat "$rx_packets_file" 2>/dev/null || echo "0")
            local tx_packets=$(cat "$tx_packets_file" 2>/dev/null || echo "0")
            
            # Convert bytes to MB
            local rx_mb=$(echo "scale=2; $rx_bytes / 1024 / 1024" | bc)
            local tx_mb=$(echo "scale=2; $tx_bytes / 1024 / 1024" | bc)
            
            if [ "$interface_count" -eq 0 ]; then
                network_data="${iface_name}|${rx_mb}|${tx_mb}|${rx_packets}|${tx_packets}"
            else
                network_data="${network_data};${iface_name}|${rx_mb}|${tx_mb}|${rx_packets}|${tx_packets}"
            fi
            
            echo "  Interface:      $iface_name"
            echo "    RX:           ${rx_mb} MB (${rx_packets} packets)"
            echo "    TX:           ${tx_mb} MB (${tx_packets} packets)"
            
            interface_count=$((interface_count + 1))
        fi
    done
    
    if [ "$interface_count" -eq 0 ]; then
        network_data="None|0|0|0|0"
        echo "  No network interfaces found"
    fi
    
    # Store metrics
    METRICS[NETWORK_DATA]="$network_data"
    METRICS[NETWORK_COUNT]="$interface_count"
    
    echo ""
    log_info "Network metrics collected: Interfaces=$interface_count"
}

# [6/10] System Load Metrics
collect_load_metrics() {
    log_info "[6/10] Collecting System Load Metrics..."
    echo "[6/10] Collecting System Load Metrics..."
    
    # Uptime
    local uptime_seconds=$(cat /proc/uptime 2>/dev/null | awk '{print int($1)}')
    if [ -z "$uptime_seconds" ]; then
        uptime_seconds=0
    fi
    
    local uptime_days=$((uptime_seconds / 86400))
    local uptime_hours=$(((uptime_seconds % 86400) / 3600))
    local uptime_minutes=$(((uptime_seconds % 3600) / 60))
    local uptime_formatted="${uptime_days}d ${uptime_hours}h ${uptime_minutes}m"
    
    # Process count
    local process_count=$(ps aux 2>/dev/null | wc -l)
    process_count=$((process_count - 1))  # Subtract header line
    if [ "$process_count" -lt 0 ]; then
        process_count=0
    fi
    
    # Load averages
    local load_1m=$(cat /proc/loadavg 2>/dev/null | awk '{print $1}')
    local load_5m=$(cat /proc/loadavg 2>/dev/null | awk '{print $2}')
    local load_15m=$(cat /proc/loadavg 2>/dev/null | awk '{print $3}')
    
    if [ -z "$load_1m" ]; then
        load_1m="0.00"
    fi
    if [ -z "$load_5m" ]; then
        load_5m="0.00"
    fi
    if [ -z "$load_15m" ]; then
        load_15m="0.00"
    fi
    
    # Store metrics
    METRICS[UPTIME_SECONDS]="$uptime_seconds"
    METRICS[UPTIME_FORMATTED]="$uptime_formatted"
    METRICS[UPTIME_DAYS]="$uptime_days"
    METRICS[PROCESS_COUNT]="$process_count"
    METRICS[LOAD_1M]="$load_1m"
    METRICS[LOAD_5M]="$load_5m"
    METRICS[LOAD_15M]="$load_15m"
    
    # Display
    echo "  Uptime:         $uptime_formatted"
    echo "  Process Count:  $process_count"
    echo "  Load Average:   ${load_1m} (1m), ${load_5m} (5m), ${load_15m} (15m)"
    echo ""
    
    log_info "Load metrics collected: Uptime=$uptime_formatted, Processes=$process_count"
}

# [7/10] GPU Utilization
collect_gpu_metrics() {
    log_info "[7/10] Collecting GPU Metrics..."
    echo "[7/10] Collecting GPU Metrics..."
    
    local gpu_detected=0
    local gpu_type="None"
    local gpu_name="N/A"
    local gpu_memory_used="0"
    local gpu_memory_total="0"
    local gpu_utilization="0"
    
    # Check for NVIDIA GPU
    local nvidia_cmd=""
    if command -v nvidia-smi &>/dev/null; then
        nvidia_cmd="nvidia-smi"
    elif command -v nvidia-smi.exe &>/dev/null; then
        nvidia_cmd="nvidia-smi.exe"
    fi

    if [ -n "$nvidia_cmd" ]; then
        local nvidia_output=$($nvidia_cmd --query-gpu=name,memory.used,memory.total,utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>/dev/null | tr -d '\r')
        if [ $? -eq 0 ] && [ -n "$nvidia_output" ]; then
            gpu_detected=1
            gpu_type="NVIDIA"
            gpu_name=$(echo "$nvidia_output" | cut -d',' -f1 | sed 's/^[ \t]*//')
            gpu_memory_used=$(echo "$nvidia_output" | cut -d',' -f2 | sed 's/^[ \t]*//')
            gpu_memory_total=$(echo "$nvidia_output" | cut -d',' -f3 | sed 's/^[ \t]*//')
            gpu_utilization=$(echo "$nvidia_output" | cut -d',' -f4 | sed 's/^[ \t]*//')
            local gpu_temp=$(echo "$nvidia_output" | cut -d',' -f5 | sed 's/^[ \t]*//')
            
            echo "  GPU Type:       $gpu_type"
            echo "  GPU Name:       $gpu_name"
            echo "  Memory Used:    ${gpu_memory_used} MB"
            echo "  Memory Total:   ${gpu_memory_total} MB"
            echo "  Utilization:    ${gpu_utilization}%"
            echo "  Temperature:    ${gpu_temp}°C"
            
            METRICS[GPU_TEMP]="$gpu_temp"
        fi
    fi
    
    # Check for AMD GPU (if NVIDIA not found)
    if [ $gpu_detected -eq 0 ]; then
        local vram_used_file="/sys/class/drm/card0/device/mem_info_vram_used"
        local vram_total_file="/sys/class/drm/card0/device/mem_info_vram_total"
        
        if [ -r "$vram_used_file" ] && [ -r "$vram_total_file" ]; then
            local vram_used_bytes=$(cat "$vram_used_file" 2>/dev/null || echo "0")
            local vram_total_bytes=$(cat "$vram_total_file" 2>/dev/null || echo "0")
            
            # Try to find AMD temp file (best effort)
            local amd_temp="N/A"
            local temp_file="/sys/class/drm/card0/device/hwmon/hwmon*/temp1_input"
            # referencing based on glob expansion which might not work directly in variable, 
            # so we try to cat the first match if exists
            local found_temp_file=$(ls /sys/class/drm/card0/device/hwmon/hwmon*/temp1_input 2>/dev/null | head -n 1)
            if [ -n "$found_temp_file" ] && [ -r "$found_temp_file" ]; then
                local raw_amd_temp=$(cat "$found_temp_file" 2>/dev/null)
                if [ -n "$raw_amd_temp" ]; then
                     amd_temp=$((raw_amd_temp / 1000))
                fi
            fi
            
            if [ "$vram_total_bytes" -gt 0 ]; then
                gpu_detected=1
                gpu_type="AMD"
                gpu_name="AMD GPU"
                gpu_memory_used=$(echo "scale=2; $vram_used_bytes / 1024 / 1024" | bc)
                gpu_memory_total=$(echo "scale=2; $vram_total_bytes / 1024 / 1024" | bc)
                
                echo "  GPU Type:       $gpu_type"
                echo "  GPU Name:       $gpu_name"
                echo "  Memory Used:    ${gpu_memory_used} MB"
                echo "  Memory Total:   ${gpu_memory_total} MB"
                if [ "$amd_temp" != "N/A" ]; then
                     echo "  Temperature:    ${amd_temp}°C"
                     METRICS[GPU_TEMP]="$amd_temp"
                fi
            fi
        fi
    fi
    
    if [ $gpu_detected -eq 0 ]; then
        echo "  GPU:            No GPU detected"
        METRICS[GPU_TEMP]="N/A"
    fi
    
    # Store metrics
    METRICS[GPU_DETECTED]="$gpu_detected"
    METRICS[GPU_TYPE]="$gpu_type"
    METRICS[GPU_NAME]="$gpu_name"
    METRICS[GPU_MEMORY_USED]="$gpu_memory_used"
    METRICS[GPU_MEMORY_TOTAL]="$gpu_memory_total"
    METRICS[GPU_UTILIZATION]="$gpu_utilization"
    
    echo ""
    log_info "GPU metrics collected: Type=$gpu_type, Detected=$gpu_detected"
}

# [8/10] System Temperature
collect_temperature_metrics() {
    log_info "[8/10] Collecting Temperature Metrics..."
    echo "[8/10] Collecting Temperature Metrics..."
    
    local temp_value=""
    local temp_source=""
    
    # --------------------------------------------------------------------------
    # USER PROVIDED LOGIC: Real Sensor Check -> Smart Simulation Fallback
    # --------------------------------------------------------------------------
    
    # 1. Try Real CPU Temp (lm-sensors)
    # Using specific grep pattern from user snippet
    local sensor_temp=$(sensors 2>/dev/null | grep -m 1 -E 'Package id 0:|Tctl:|Core 0:|temp1:' | awk '{print $2, $3, $4}' | grep -o '[0-9.]*' | head -n1)
    
    if [ -n "$sensor_temp" ]; then
        # Remove floating point for integer arithmetic later or use bc
        temp_value=$(echo "$sensor_temp" | cut -d. -f1)
        temp_source="Real Sensor (lm-sensors)"
    fi

    # 2. Try Thermal Zone (if sensors failed)
    if [ -z "$temp_value" ]; then
        local raw_temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
        if [ -n "$raw_temp" ] && [ "$raw_temp" -gt 0 ]; then
            temp_value=$((raw_temp / 1000))
            temp_source="Real Sensor (thermal_zone)"
        fi
    fi
    
    # 3. Smart Simulation (AESL Case / Fallback)
    # Logic: Base Temp (42) + (CPU Load / 3) + Random Jitter (0-3)
    if [ -z "$temp_value" ] || [ "$temp_value" -eq 0 ]; then
        local cpu_usage="${METRICS[CPU_USAGE]}"
        local usage_int=0
        if [ -n "$cpu_usage" ]; then
             usage_int=$(echo "$cpu_usage" | cut -d. -f1)
        fi
        
        # Jitter calculation
        local jitter=$((RANDOM % 3))
        local added_heat=$((usage_int / 3))
        local simulated_temp=$((42 + added_heat + jitter))
        
        temp_value="$simulated_temp"
        temp_source="Smart Simulation (Load + Jitter)"
    fi
    
    # Store metrics
    METRICS[TEMPERATURE]="$temp_value"
    METRICS[TEMPERATURE_SOURCE]="$temp_source"
    
    # Display
    echo "  Temperature:    ${temp_value}°C (from $temp_source)"
    echo ""
    
    log_info "Temperature metrics collected: Temp=${temp_value}°C, Source=$temp_source"
}

# [9/10] Process Top Users
collect_top_processes() {
    log_info "[9/10] Collecting Top Processes..."
    echo "[9/10] Collecting Top Processes..."
    
    local top_processes=""
    
    # Get top 5 processes by memory
    local ps_output=$(ps aux --sort=-%mem 2>/dev/null | head -6 | tail -5)
    
    if [ -n "$ps_output" ]; then
        echo "  Top 5 Processes by Memory:"
        echo "  PID     USER       MEM%    COMMAND"
        echo "  ----------------------------------------"
        
        local count=0
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                local pid=$(echo "$line" | awk '{print $2}')
                local user=$(echo "$line" | awk '{print $1}')
                local mem=$(echo "$line" | awk '{print $4}')
                local cmd=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ $//')
                local cmd_short=$(echo "$cmd" | cut -c1-30)
                
                printf "  %-7s %-10s %-7s %s\n" "$pid" "$user" "${mem}%" "$cmd_short"
                
                if [ $count -eq 0 ]; then
                    top_processes="${pid}|${user}|${mem}|${cmd_short}"
                else
                    top_processes="${top_processes};${pid}|${user}|${mem}|${cmd_short}"
                fi
                
                count=$((count + 1))
            fi
        done <<< "$ps_output"
    else
        top_processes="N/A|N/A|0|N/A"
        echo "  No process information available"
    fi
    
    # Store metrics
    METRICS[TOP_PROCESSES]="$top_processes"
    
    echo ""
    log_info "Top processes collected: Count=5"
}

# [10/10] Alert System
check_critical_alerts() {
    log_info "[10/10] Checking Critical Alerts..."
    echo "[10/10] Checking Critical Alerts..."
    
    local alert_count=0
    
    # Memory alert (>90%)
    local mem_percent=$(echo "${METRICS[MEM_USED_PERCENT]}" | cut -d. -f1)
    if [ -n "$mem_percent" ] && [ "$mem_percent" -gt 90 ]; then
        log_warning "ALERT: Memory usage is ${METRICS[MEM_USED_PERCENT]}% (threshold: 90%)"
        echo "  ⚠ ALERT: Memory usage is ${METRICS[MEM_USED_PERCENT]}% (threshold: 90%)"
        alert_count=$((alert_count + 1))
    fi
    
    # Disk alert (>90%)
    local disk_percent="${METRICS[DISK_USED_PERCENT]}"
    if [ -n "$disk_percent" ] && [ "$disk_percent" -gt 90 ]; then
        log_warning "ALERT: Disk usage is ${disk_percent}% (threshold: 90%)"
        echo "  ⚠ ALERT: Disk usage is ${disk_percent}% (threshold: 90%)"
        alert_count=$((alert_count + 1))
    fi
    
    # CPU load alert (load > number of cores)
    local load_1m="${METRICS[LOAD_1M]}"
    local cpu_cores="${METRICS[CPU_CORES]}"
    if [ -n "$load_1m" ] && [ -n "$cpu_cores" ]; then
        local load_int=$(echo "$load_1m" | cut -d. -f1)
        if [ "$load_int" -gt "$cpu_cores" ]; then
            log_warning "ALERT: CPU load is $load_1m (cores: $cpu_cores)"
            echo "  ⚠ ALERT: CPU load is $load_1m (cores: $cpu_cores)"
            alert_count=$((alert_count + 1))
        fi
    fi
    
    if [ $alert_count -eq 0 ]; then
        echo "  ✓ No critical alerts"
    fi
    
    echo ""
    log_info "Alert check completed: $alert_count alerts found"
}

################################################################################
# CSV Export Function
################################################################################

export_csv_data() {
    log_info "Exporting CSV data..."
    
    # Updated header to reflect multi-disk summary, GPU metrics, and Temperatures
    local csv_header="Timestamp,CPU_Usage(%),Memory_Total(GB),Memory_Used(GB),Memory_Free(GB),Memory_Used(%),Disk_Usage_Summary,GPU_Utilization(%),GPU_Memory_Used(MB),CPU_Temp(C),GPU_Temp(C),Process_Count,Load_1m,Uptime_Days"
    
    # Create CSV file with header if it doesn't exist
    if [ ! -f "$CSV_FILE" ]; then
        echo "$csv_header" > "$CSV_FILE"
    else
        # Optional: Check if header matches (simple heuristic) - if old header, maybe backup or warn?
        # For this simplified script, we assume append is fine, but strictly speaking checking headers is safer.
        # We will just append.
        :
    fi
    
    # Prepare data row
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local cpu_usage="${METRICS[CPU_USAGE]}"
    local mem_total="${METRICS[MEM_TOTAL]}"
    local mem_used="${METRICS[MEM_USED]}"
    local mem_free="${METRICS[MEM_FREE]}"
    local mem_used_percent="${METRICS[MEM_USED_PERCENT]}"
    
    # Hardware Stats
    local gpu_util="${METRICS[GPU_UTILIZATION]}"
    local gpu_mem="${METRICS[GPU_MEMORY_USED]}"
    if [ -z "$gpu_util" ]; then gpu_util="0"; fi
    if [ -z "$gpu_mem" ]; then gpu_mem="0"; fi
    
    local cpu_temp="${METRICS[TEMPERATURE]}"
    local gpu_temp="${METRICS[GPU_TEMP]}"
    if [ -z "$cpu_temp" ]; then cpu_temp="N/A"; fi
    if [ -z "$gpu_temp" ]; then gpu_temp="N/A"; fi

    # Build Multi-Disk Summary
    local disk_summary=""
    if [ -n "${METRICS[DISK_DATA_LIST]}" ]; then
        IFS=';' read -ra DISKS <<< "${METRICS[DISK_DATA_LIST]}"
        for disk in "${DISKS[@]}"; do
             IFS='|' read -ra DSK <<< "$disk"
             if [ ${#DSK[@]} -ge 6 ]; then
                 local mount=${DSK[1]}
                 local pct=${DSK[5]}
                 if [ -z "$disk_summary" ]; then
                     disk_summary="${mount}:${pct}%"
                 else
                     disk_summary="${disk_summary}|${mount}:${pct}%"
                 fi
             fi
        done
    else
        disk_summary="N/A"
    fi
    
    local process_count="${METRICS[PROCESS_COUNT]}"
    local load_1m="${METRICS[LOAD_1M]}"
    local uptime_days="${METRICS[UPTIME_DAYS]}"
    
    # Append data row
    echo "${timestamp},${cpu_usage},${mem_total},${mem_used},${mem_free},${mem_used_percent},${disk_summary},${gpu_util},${gpu_mem},${cpu_temp},${gpu_temp},${process_count},${load_1m},${uptime_days}" >> "$CSV_FILE"
    
    log_info "CSV data exported to $CSV_FILE"
}

################################################################################
# HTML Report Generation
################################################################################

generate_html_report() {
    log_info "Generating HTML report..."
    
    local hostname=$(hostname 2>/dev/null || echo "Unknown")
    local os_info=""
    # Determine if running in WSL
    if grep -qEi "(microsoft|wsl)" /proc/version &>/dev/null; then
        os_info="WSL (Windows Subsystem for Linux)"
    else
        os_info=$(cat /etc/os-release 2>/dev/null | grep "^PRETTY_NAME" | cut -d= -f2 | tr -d '"' || echo "Linux")
    fi
    
    local report_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Calculate progress bar CSS classes
    local mem_percent_int=$(echo "${METRICS[MEM_USED_PERCENT]}" | cut -d. -f1)
    local mem_progress_class=""
    if [ -n "$mem_percent_int" ] && [ "$mem_percent_int" -gt 90 ]; then
        mem_progress_class="critical"
    elif [ -n "$mem_percent_int" ] && [ "$mem_percent_int" -gt 70 ]; then
        mem_progress_class="warning"
    fi
    
    local disk_percent_int="${METRICS[DISK_USED_PERCENT]}"
    local disk_progress_class=""
    if [ -n "$disk_percent_int" ] && [ "$disk_percent_int" -gt 90 ]; then
        disk_progress_class="critical"
    elif [ -n "$disk_percent_int" ] && [ "$disk_percent_int" -gt 70 ]; then
        disk_progress_class="warning"
    fi
    
    cat > "$HTML_REPORT" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>System Monitoring Report</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
            min-height: 100vh;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 10px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
            overflow: hidden;
        }
        
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 40px;
            text-align: center;
        }
        
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        
        .header p {
            font-size: 1.1em;
            opacity: 0.9;
        }
        
        .content {
            padding: 30px;
        }
        
        .section {
            margin-bottom: 30px;
            padding: 20px;
            background: #f8f9fa;
            border-radius: 8px;
            border-left: 4px solid #667eea;
        }
        
        .section h2 {
            color: #667eea;
            margin-bottom: 15px;
            font-size: 1.5em;
        }
        
        .metric-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 15px;
            margin-top: 15px;
        }
        
        .metric-item {
            background: white;
            padding: 15px;
            border-radius: 5px;
            box-shadow: 0 2px 5px rgba(0,0,0,0.1);
        }
        
        .metric-label {
            font-weight: bold;
            color: #555;
            margin-bottom: 5px;
        }
        
        .metric-value {
            font-size: 1.3em;
            color: #333;
        }
        
        .progress-bar {
            width: 100%;
            height: 25px;
            background: #e0e0e0;
            border-radius: 12px;
            overflow: hidden;
            margin-top: 10px;
        }
        
        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, #4caf50, #8bc34a);
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: bold;
            font-size: 0.9em;
            transition: width 0.3s ease;
        }
        
        .progress-fill.warning {
            background: linear-gradient(90deg, #ff9800, #ffc107);
        }
        
        .progress-fill.critical {
            background: linear-gradient(90deg, #f44336, #e91e63);
        }
        
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 15px;
        }
        
        table th, table td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }
        
        table th {
            background: #667eea;
            color: white;
            font-weight: bold;
        }
        
        table tr:hover {
            background: #f5f5f5;
        }
        
        .status-badge {
            display: inline-block;
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 0.9em;
            font-weight: bold;
        }
        
        .status-success {
            background: #4caf50;
            color: white;
        }
        
        .status-warning {
            background: #ff9800;
            color: white;
        }
        
        .status-danger {
            background: #f44336;
            color: white;
        }
        
        .footer {
            text-align: center;
            padding: 20px;
            background: #f8f9fa;
            color: #666;
            font-size: 0.9em;
        }
        
        @media (max-width: 768px) {
            .header h1 {
                font-size: 1.8em;
            }
            
            .metric-grid {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>System Monitoring Report</h1>
            <p>Comprehensive System Monitoring Solution - Arab Academy 12th Project</p>
        </div>
        
        <div class="content">
            <!-- System Information -->
            <div class="section">
                <h2>System Information</h2>
                <div class="metric-grid">
                    <div class="metric-item">
                        <div class="metric-label">Hostname</div>
                        <div class="metric-value">$hostname</div>
                    </div>
                    <div class="metric-item">
                        <div class="metric-label">Operating System</div>
                        <div class="metric-value">$os_info</div>
                    </div>
                    <div class="metric-item">
                        <div class="metric-label">Report Time</div>
                        <div class="metric-value">$report_time</div>
                    </div>
                    <div class="metric-item">
                        <div class="metric-label">Uptime</div>
                        <div class="metric-value">${METRICS[UPTIME_FORMATTED]}</div>
                    </div>
                </div>
            </div>
            
            <!-- CPU Performance -->
            <div class="section">
                <h2>CPU Performance</h2>
                <div class="metric-grid">
                    <div class="metric-item">
                        <div class="metric-label">CPU Model</div>
                        <div class="metric-value">${METRICS[CPU_MODEL]}</div>
                    </div>
                    <div class="metric-item">
                        <div class="metric-label">CPU Cores</div>
                        <div class="metric-value">${METRICS[CPU_CORES]}</div>
                    </div>
                    <div class="metric-item">
                        <div class="metric-label">CPU Usage</div>
                        <div class="metric-value">${METRICS[CPU_USAGE]}%</div>
                    </div>
                    <div class="metric-item">
                        <div class="metric-label">Load Average (1m)</div>
                        <div class="metric-value">${METRICS[LOAD_1M]}</div>
                    </div>
                </div>
                <div class="progress-bar">
                    <div class="progress-fill" style="width: ${METRICS[CPU_USAGE]}%">${METRICS[CPU_USAGE]}%</div>
                </div>
            </div>
            
            <!-- Memory Consumption -->
            <div class="section">
                <h2>Memory Consumption</h2>
                <div class="metric-grid">
                    <div class="metric-item">
                        <div class="metric-label">Total Memory</div>
                        <div class="metric-value">${METRICS[MEM_TOTAL]} GB</div>
                    </div>
                    <div class="metric-item">
                        <div class="metric-label">Used Memory</div>
                        <div class="metric-value">${METRICS[MEM_USED]} GB</div>
                    </div>
                    <div class="metric-item">
                        <div class="metric-label">Free Memory</div>
                        <div class="metric-value">${METRICS[MEM_FREE]} GB</div>
                    </div>
                    <div class="metric-item">
                        <div class="metric-label">Available Memory</div>
                        <div class="metric-value">${METRICS[MEM_AVAILABLE]} GB</div>
                    </div>
                </div>
                <div class="progress-bar">
                    <div class="progress-fill ${mem_progress_class}" style="width: ${METRICS[MEM_USED_PERCENT]}%">${METRICS[MEM_USED_PERCENT]}%</div>
                </div>
            </div>
            
            <!-- Disk Usage -->
            <div class="section">
                <h2>Disk Usage</h2>
                <table>
                    <thead>
                        <tr>
                            <th>Filesystem</th>
                            <th>Mount Point</th>
                            <th>Total</th>
                            <th>Used</th>
                            <th>Available</th>
                            <th>Usage</th>
                        </tr>
                    </thead>
                    <tbody>
EOF
    # Add disk rows
    if [ -n "${METRICS[DISK_DATA_LIST]}" ]; then
        IFS=';' read -ra DISKS <<< "${METRICS[DISK_DATA_LIST]}"
        for disk in "${DISKS[@]}"; do
            IFS='|' read -ra DSK <<< "$disk"
            if [ ${#DSK[@]} -ge 6 ]; then
                # Determine color for usage
                local usage_val=${DSK[5]}
                local usage_style=""
                if [ "$usage_val" -gt 90 ]; then
                    usage_style="style=\"color: #f44336; font-weight: bold;\""
                elif [ "$usage_val" -gt 75 ]; then
                     usage_style="style=\"color: #ff9800; font-weight: bold;\""
                fi

                echo "                        <tr>" >> "$HTML_REPORT"
                echo "                            <td>${DSK[0]}</td>" >> "$HTML_REPORT"
                echo "                            <td>${DSK[1]}</td>" >> "$HTML_REPORT"
                echo "                            <td>${DSK[2]}</td>" >> "$HTML_REPORT"
                echo "                            <td>${DSK[3]}</td>" >> "$HTML_REPORT"
                echo "                            <td>${DSK[4]}</td>" >> "$HTML_REPORT"
                echo "                            <td $usage_style>${DSK[5]}%</td>" >> "$HTML_REPORT"
                echo "                        </tr>" >> "$HTML_REPORT"
            fi
        done
    else
        echo "                        <tr><td colspan=\"6\">No disk information available</td></tr>" >> "$HTML_REPORT"
    fi
    
    cat >> "$HTML_REPORT" << EOF
                    </tbody>
                </table>
            </div>
            
            <!-- Network Interfaces -->
            <div class="section">
                <h2>Network Interfaces</h2>
                <table>
                    <thead>
                        <tr>
                            <th>Interface</th>
                            <th>RX (MB)</th>
                            <th>TX (MB)</th>
                            <th>RX Packets</th>
                            <th>TX Packets</th>
                        </tr>
                    </thead>
                    <tbody>
EOF

    # Add network interface rows
    if [ -n "${METRICS[NETWORK_DATA]}" ] && [ "${METRICS[NETWORK_DATA]}" != "None|0|0|0|0" ]; then
        IFS=';' read -ra NETWORKS <<< "${METRICS[NETWORK_DATA]}"
        for network in "${NETWORKS[@]}"; do
            IFS='|' read -ra NET <<< "$network"
            if [ ${#NET[@]} -ge 5 ]; then
                echo "                        <tr>" >> "$HTML_REPORT"
                echo "                            <td>${NET[0]}</td>" >> "$HTML_REPORT"
                echo "                            <td>${NET[1]}</td>" >> "$HTML_REPORT"
                echo "                            <td>${NET[2]}</td>" >> "$HTML_REPORT"
                echo "                            <td>${NET[3]}</td>" >> "$HTML_REPORT"
                echo "                            <td>${NET[4]}</td>" >> "$HTML_REPORT"
                echo "                        </tr>" >> "$HTML_REPORT"
            fi
        done
    else
        echo "                        <tr><td colspan=\"5\">No network interfaces found</td></tr>" >> "$HTML_REPORT"
    fi

    cat >> "$HTML_REPORT" << EOF
                    </tbody>
                </table>
            </div>
            
            <!-- Process Information -->
            <div class="section">
                <h2>Process Information</h2>
                <div class="metric-item">
                    <div class="metric-label">Total Processes</div>
                    <div class="metric-value">${METRICS[PROCESS_COUNT]}</div>
                </div>
                <h3 style="margin-top: 20px; margin-bottom: 10px;">Top 5 Processes by Memory</h3>
                <table>
                    <thead>
                        <tr>
                            <th>PID</th>
                            <th>User</th>
                            <th>Memory %</th>
                            <th>Command</th>
                        </tr>
                    </thead>
                    <tbody>
EOF

    # Add top processes rows
    if [ -n "${METRICS[TOP_PROCESSES]}" ] && [ "${METRICS[TOP_PROCESSES]}" != "N/A|N/A|0|N/A" ]; then
        IFS=';' read -ra PROCESSES <<< "${METRICS[TOP_PROCESSES]}"
        for process in "${PROCESSES[@]}"; do
            IFS='|' read -ra PROC <<< "$process"
            if [ ${#PROC[@]} -ge 4 ]; then
                echo "                        <tr>" >> "$HTML_REPORT"
                echo "                            <td>${PROC[0]}</td>" >> "$HTML_REPORT"
                echo "                            <td>${PROC[1]}</td>" >> "$HTML_REPORT"
                echo "                            <td>${PROC[2]}%</td>" >> "$HTML_REPORT"
                echo "                            <td>${PROC[3]}</td>" >> "$HTML_REPORT"
                echo "                        </tr>" >> "$HTML_REPORT"
            fi
        done
    else
        echo "                        <tr><td colspan=\"4\">No process information available</td></tr>" >> "$HTML_REPORT"
    fi

    cat >> "$HTML_REPORT" << EOF
                    </tbody>
                </table>
            </div>
            
            <!-- System Temperature -->
            <div class="section">
                <h2>System Temperature</h2>
                <div class="metric-item">
                    <div class="metric-label">Temperature</div>
                    <div class="metric-value">${METRICS[TEMPERATURE]}°C</div>
                </div>
                <div class="metric-item">
                    <div class="metric-label">Source</div>
                    <div class="metric-value">${METRICS[TEMPERATURE_SOURCE]}</div>
                </div>
            </div>
            
            <!-- GPU Status -->
            <div class="section">
                <h2>GPU Status</h2>
EOF

    if [ "${METRICS[GPU_DETECTED]}" = "1" ]; then
        cat >> "$HTML_REPORT" << EOF
                <div class="metric-grid">
                    <div class="metric-item">
                        <div class="metric-label">GPU Type</div>
                        <div class="metric-value">${METRICS[GPU_TYPE]}</div>
                    </div>
                    <div class="metric-item">
                        <div class="metric-label">GPU Name</div>
                        <div class="metric-value">${METRICS[GPU_NAME]}</div>
                    </div>
                    <div class="metric-item">
                        <div class="metric-label">Memory Used</div>
                        <div class="metric-value">${METRICS[GPU_MEMORY_USED]} MB</div>
                    </div>
                    <div class="metric-item">
                        <div class="metric-label">Memory Total</div>
                        <div class="metric-value">${METRICS[GPU_MEMORY_TOTAL]} MB</div>
                    </div>
EOF
        if [ -n "${METRICS[GPU_UTILIZATION]}" ] && [ "${METRICS[GPU_UTILIZATION]}" != "0" ]; then
            cat >> "$HTML_REPORT" << EOF
                    <div class="metric-item">
                        <div class="metric-label">Utilization</div>
                        <div class="metric-value">${METRICS[GPU_UTILIZATION]}%</div>
                    </div>
EOF
        fi
        cat >> "$HTML_REPORT" << EOF
                </div>
EOF
    else
        cat >> "$HTML_REPORT" << EOF
                <div class="metric-item">
                    <div class="metric-value">No GPU detected</div>
                </div>
EOF
    fi

    cat >> "$HTML_REPORT" << EOF
            </div>
            
            <!-- SMART Status -->
            <div class="section">
                <h2>SMART Status</h2>
                <div class="metric-item">
                    <div class="metric-label">Status</div>
                    <div class="metric-value">${METRICS[SMART_STATUS]}</div>
                </div>
                <div class="metric-item">
                    <div class="metric-label">Health</div>
                    <div class="metric-value">${METRICS[SMART_HEALTH]}</div>
                </div>
            </div>
        </div>
        
        <div class="footer">
            <p>Report generated on $report_time</p>
            <p>System Monitoring Solution - Arab Academy 12th Project</p>
        </div>
    </div>
</body>
</html>
EOF

    log_info "HTML report generated: $HTML_REPORT"
}

################################################################################
# Main Execution Flow
################################################################################

main() {
    # Setup
    setup_directories
    display_header
    
    # Collect all metrics
    collect_cpu_metrics
    collect_memory_metrics
    collect_disk_metrics
    collect_smart_status
    collect_network_metrics
    collect_load_metrics
    collect_gpu_metrics
    collect_temperature_metrics
    collect_top_processes
    check_critical_alerts
    
    # Export and generate reports
    export_csv_data
    generate_html_report
    
    # Completion message
    echo ""
    echo "================================================================================"
    echo "  Monitoring Complete!"
    echo "================================================================================"
    echo ""
    echo "  Log File:    $LOG_FILE"
    echo "  CSV Data:    $CSV_FILE"
    echo "  HTML Report: $HTML_REPORT"
    echo ""
    echo "================================================================================"
    echo ""
    
    log_info "System monitoring completed successfully"
}

# Run main function
main

