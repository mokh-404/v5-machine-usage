#!/bin/bash

################################################################################
# Unified System Monitoring Script
# Works on Linux, macOS, and Windows (via WSL 1)
# Uses feature detection to extract real hardware metrics
# "Breaks isolation" on WSL 1 by using available host tools (nvidia-smi.exe)
################################################################################

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
REPORT_DIR="${SCRIPT_DIR}/reports"
DATA_DIR="${SCRIPT_DIR}/data"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/system_monitor_${TIMESTAMP}.log"
CSV_FILE="${DATA_DIR}/metrics_${TIMESTAMP}.csv"
HTML_REPORT="${REPORT_DIR}/report_${TIMESTAMP}.html"

# Global metric storage
declare -A METRICS

################################################################################
# Utilities & Logging
################################################################################

log_message() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

log_info() { log_message "INFO: $1"; }
log_warn() { log_message "WARNING: $1"; }
log_error() { log_message "ERROR: $1"; }

setup_directories() {
    mkdir -p "$LOG_DIR" "$REPORT_DIR" "$DATA_DIR"
}

display_header() {
    echo ""
    echo "================================================================================"
    echo "  Unified System Monitoring Solution"
    echo "================================================================================"
    echo ""
    echo "  Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "  Log File:  $LOG_FILE"
    echo ""
    log_info "Starting system monitoring..."
}

################################################################################
# Metric Collection
################################################################################

# [1/10] CPU Metrics
collect_cpu_metrics() {
    log_info "[1/10] Collecting CPU Metrics..."
    echo "[1/10] Collecting CPU Metrics..."

    local model="Unknown"
    local cores=1
    local usage=0
    local load="0.00"

    # -- Model & Cores --
    if command -v sysctl >/dev/null 2>&1; then
        local m=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
        [ -n "$m" ] && model="$m"
        local c=$(sysctl -n hw.logicalcpu 2>/dev/null)
        [ -n "$c" ] && cores="$c"
    fi
    if [ -r /proc/cpuinfo ]; then
        local m=$(grep "^model name" /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^[ \t]*//')
        [ -n "$m" ] && model="$m"
        local c=$(grep -c "^processor" /proc/cpuinfo)
        [ -n "$c" ] && [ "$c" -gt 0 ] && cores="$c"
    fi

    # -- Usage --
    if [ "$(uname)" = "Darwin" ]; then
        local cpu_str=$(top -l 1 | grep "CPU usage" | head -1)
        local user=$(echo "$cpu_str" | awk '{print $3}' | sed 's/%//')
        local sys=$(echo "$cpu_str" | awk '{print $5}' | sed 's/%//')
        if [ -n "$user" ] && [ -n "$sys" ]; then
             usage=$(echo "$user + $sys" | bc)
        fi
    fi
    if [ -r /proc/stat ]; then
        local cpu_line1=$(grep "^cpu " /proc/stat)
        sleep 1
        local cpu_line2=$(grep "^cpu " /proc/stat)
        
        read -r _ u1 n1 s1 i1 _ <<< "$cpu_line1"
        read -r _ u2 n2 s2 i2 _ <<< "$cpu_line2"
        
        local total1=$((u1 + n1 + s1 + i1))
        local total2=$((u2 + n2 + s2 + i2))
        local delta_total=$((total2 - total1))
        local delta_idle=$((i2 - i1))
        
        if [ "$delta_total" -gt 0 ]; then
             local delta_used=$((delta_total - delta_idle))
             usage=$(echo "scale=2; ($delta_used * 100) / $delta_total" | bc 2>/dev/null || echo 0)
        fi
    fi

    # -- Load Average --
    if command -v sysctl >/dev/null 2>&1; then
         local l=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')
         [ -n "$l" ] && load="$l"
    fi
    if [ -r /proc/loadavg ]; then
         load=$(awk '{print $1}' /proc/loadavg)
    fi

    METRICS[CPU_MODEL]="$model"
    METRICS[CPU_CORES]="$cores"
    METRICS[CPU_USAGE]="$usage"
    METRICS[LOAD_AVG]="$load"

    echo "  Model: $model"
    echo "  Cores: $cores"
    echo "  Usage: ${usage}%"
    echo "  Load:  $load"
    echo ""
}

# [2/10] Memory Metrics
collect_memory_metrics() {
    log_info "[2/10] Collecting Memory Metrics..."
    echo "[2/10] Collecting Memory Metrics..."

    local total_gb=0
    local free_gb=0
    local used_gb=0
    local perm=0

    # macOS
    if command -v vm_stat >/dev/null 2>&1 && command -v sysctl >/dev/null 2>&1; then
        local page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
        local total_bytes=$(sysctl -n hw.memsize 2>/dev/null)
        
        local pages_free=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
        local pages_speculative=$(vm_stat | grep "Pages speculative" | awk '{print $3}' | sed 's/\.//' || echo 0)
        
        local free_bytes=$(( (pages_free + pages_speculative) * page_size ))
        
        total_gb=$(echo "scale=2; $total_bytes / 1024 / 1024 / 1024" | bc)
        free_gb=$(echo "scale=2; $free_bytes / 1024 / 1024 / 1024" | bc)
    fi

    # Linux/WSL
    if [ -r /proc/meminfo ]; then
        local t_kb=$(grep "^MemTotal:" /proc/meminfo | awk '{print $2}')
        local f_kb=$(grep "^MemAvailable:" /proc/meminfo | awk '{print $2}') || $(grep "^MemFree:" /proc/meminfo | awk '{print $2}')
        [ -z "$f_kb" ] && f_kb=$(grep "^MemFree:" /proc/meminfo | awk '{print $2}')
        
        if [ -n "$t_kb" ]; then
            total_gb=$(echo "scale=2; $t_kb / 1024 / 1024" | bc)
            free_gb=$(echo "scale=2; $f_kb / 1024 / 1024" | bc)
        fi
    fi

    used_gb=$(echo "scale=2; $total_gb - $free_gb" | bc)
    if [ "$(echo "$total_gb > 0" | bc)" -eq 1 ]; then
        perm=$(echo "scale=2; ($used_gb * 100) / $total_gb" | bc)
    fi

    METRICS[MEM_TOTAL]="$total_gb"
    METRICS[MEM_USED]="$used_gb"
    METRICS[MEM_FREE]="$free_gb"
    METRICS[MEM_PERCENT]="$perm"

    echo "  Total: ${total_gb} GB"
    echo "  Used:  ${used_gb} GB"
    echo "  Free:  ${free_gb} GB"
    echo "  Usage: ${perm}%"
    echo ""
}

# [3/10] Disk Metrics
collect_disk_metrics() {
    log_info "[3/10] Collecting Disk Metrics..."
    echo "[3/10] Collecting Disk Metrics..."

    local path="/"
    # Handle WSL path sometimes being /mnt/c
    if [ -d "/mnt/c" ]; then
        path="/mnt/c" 
    fi
    
    local df_out=$(df -h "$path" 2>/dev/null | tail -1)
    
    local fs=$(echo "$df_out" | awk '{print $1}')
    local size=$(echo "$df_out" | awk '{print $2}')
    local used=$(echo "$df_out" | awk '{print $3}')
    local avail=$(echo "$df_out" | awk '{print $4}')
    local pcent=$(echo "$df_out" | awk '{print $5}' | sed 's/%//')

    METRICS[DISK_FS]="$fs"
    METRICS[DISK_SIZE]="$size"
    METRICS[DISK_USED]="$used"
    METRICS[DISK_AVAIL]="$avail"
    METRICS[DISK_PERCENT]="$pcent"

    echo "  Path:  $path"
    echo "  Total: $size"
    echo "  Used:  $used ($pcent%)"
    echo ""
}

# [4/10] SMART Status
collect_smart_status() {
    log_info "[4/10] Collecting SMART Status..."
    echo "[4/10] Collecting SMART Status..."
    
    local status="N/A"
    local health="N/A"

    if command -v smartctl >/dev/null 2>&1; then
        local drive="/dev/sda"
        [ -e /dev/nvme0n1 ] && drive="/dev/nvme0n1"
        [ -e /dev/disk0 ] && drive="/dev/disk0"
        
        if [ "$EUID" -eq 0 ]; then
             local out=$(smartctl -H "$drive" 2>/dev/null)
             if echo "$out" | grep -q "result: PASSED"; then
                 status="Available"
                 health="PASSED"
             elif echo "$out" | grep -q "result: FAILED"; then
                 status="Available"
                 health="FAILED"
             else
                 status="Available"
                 health="Unknown"
             fi
        else
            status="Permission Denied (Root req)"
        fi
    else
        status="smartctl not found"
    fi

    METRICS[SMART_STATUS]="$status"
    METRICS[SMART_HEALTH]="$health"
    echo "  Status: $status"
    echo "  Health: $health"
    echo ""
}

# [5/10] Network Metrics
collect_network_metrics() {
    log_info "[5/10] Collecting Network Metrics..."
    echo "[5/10] Collecting Network Metrics..."

    local net_info=""
    local found=0

    # Strategy 1: /proc/net/dev (Linux/WSL)
    # Inter-|   Receive                                                |  Transmit
    #  face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets
    if [ -r /proc/net/dev ]; then
        # Skip header lines 1 and 2
        local raw=$(tail -n +3 /proc/net/dev)
        while read -r line; do
            # Trim whitespace
            line=$(echo "$line" | sed 's/^[ \t]*//')
            [ -z "$line" ] && continue
            
            local name=$(echo "$line" | cut -d: -f1)
            local stats=$(echo "$line" | cut -d: -f2)
            
            [ "$name" = "lo" ] && continue
            
            local rx_bytes=$(echo "$stats" | awk '{print $1}')
            local tx_bytes=$(echo "$stats" | awk '{print $9}')
            
            if [ -n "$rx_bytes" ] && [ -n "$tx_bytes" ]; then
                local rx_mb=$(echo "scale=2; $rx_bytes / 1024 / 1024" | bc)
                local tx_mb=$(echo "scale=2; $tx_bytes / 1024 / 1024" | bc)
                
                net_info="${net_info}${name}|${rx_mb}|${tx_mb};"
                found=1
                echo "  $name: RX ${rx_mb} MB / TX ${tx_mb} MB"
            fi
        done <<< "$raw"
    fi

    # Strategy 2: netstat -ib (Mac)
    if [ $found -eq 0 ] && command -v netstat >/dev/null 2>&1; then
        local raw=$(netstat -ib 2>/dev/null)
        while read -r line; do
            local name=$(echo "$line" | awk '{print $1}')
            [ "$name" = "Name" ] && continue
            [ "$name" = "lo0" ] && continue
            
            local ibytes=$(echo "$line" | awk '{print $7}')
            local obytes=$(echo "$line" | awk '{print $10}')
            
            if [[ "$ibytes" =~ ^[0-9]+$ ]] && [[ "$obytes" =~ ^[0-9]+$ ]]; then
                 local rx_mb=$(echo "scale=2; $ibytes / 1024 / 1024" | bc)
                 local tx_mb=$(echo "scale=2; $obytes / 1024 / 1024" | bc)
                 if [[ "$net_info" != *"$name|"* ]]; then
                     net_info="${net_info}${name}|${rx_mb}|${tx_mb};"
                     echo "  $name: RX ${rx_mb} MB / TX ${tx_mb} MB"
                     found=1
                 fi
            fi
        done <<< "$raw"
    fi

    METRICS[NET_DATA]="$net_info"
    [ $found -eq 0 ] && echo "  No network data found"
    echo ""
}

# [6/10] Load Metrics
collect_load_metrics() {
    log_info "[6/10] Collecting Load Metrics..."
    echo "[6/10] Collecting Load Metrics..."

    local up_str=""
    if [ -r /proc/uptime ]; then
        local sec=$(awk '{print $1}' /proc/uptime | cut -d. -f1)
        local d=$((sec / 86400))
        local h=$(((sec % 86400) / 3600))
        local m=$(((sec % 3600) / 60))
        up_str="${d}d ${h}h ${m}m"
    else
        up_str=$(uptime | tr -d ',')
    fi

    local proc_cnt=$(ps -e | wc -l)
    
    METRICS[UPTIME]="$up_str"
    METRICS[PROC_COUNT]="$proc_cnt"
    
    echo "  Uptime: $up_str"
    echo "  Procs:  $proc_cnt"
    echo ""
}

# [7/10] GPU Metrics
collect_gpu_metrics() {
    log_info "[7/10] Collecting GPU Metrics..."
    echo "[7/10] Collecting GPU Metrics..."
    
    local gpu_name="N/A"
    local gpu_mem="N/A"
    local gpu_temp="N/A"
    local gpu_util="N/A"
    
    # Check for nvidia-smi (Linux) or nvidia-smi.exe (Windows/WSL)
    local nvidia_cmd=""
    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia_cmd="nvidia-smi"
    elif command -v nvidia-smi.exe >/dev/null 2>&1; then
        nvidia_cmd="nvidia-smi.exe"
    elif [ -f "/mnt/c/Windows/System32/nvidia-smi.exe" ]; then
        nvidia_cmd="/mnt/c/Windows/System32/nvidia-smi.exe"
    fi
    
    if [ -n "$nvidia_cmd" ]; then
        # Query Name, Mem Total, Temp, Utilization
        local out=$("$nvidia_cmd" --query-gpu=name,memory.total,temperature.gpu,utilization.gpu --format=csv,noheader,nounits 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$out" ]; then
            gpu_name=$(echo "$out" | cut -d, -f1 | xargs)
            gpu_mem=$(echo "$out" | cut -d, -f2 | xargs)
            gpu_temp=$(echo "$out" | cut -d, -f3 | xargs)
            gpu_util=$(echo "$out" | cut -d, -f4 | xargs)
            
            [ -n "$gpu_mem" ] && gpu_mem="${gpu_mem} MB"
            [ -n "$gpu_temp" ] && gpu_temp="${gpu_temp}°C"
            [ -n "$gpu_util" ] && gpu_util="${gpu_util}%"
        fi
    fi

    # Fallback: Mac
    if [ "$gpu_name" = "N/A" ] && command -v system_profiler >/dev/null 2>&1; then
        local gfx=$(system_profiler SPDisplaysDataType 2>/dev/null)
        local name=$(echo "$gfx" | grep "Chipset Model:" | head -1 | cut -d: -f2 | xargs)
        [ -n "$name" ] && gpu_name="$name"
        local mem=$(echo "$gfx" | grep "VRAM" | head -1 | cut -d: -f2 | xargs)
        [ -n "$mem" ] && gpu_mem="$mem"
    fi
    
    METRICS[GPU_NAME]="$gpu_name"
    METRICS[GPU_MEM]="$gpu_mem"
    METRICS[GPU_TEMP]="$gpu_temp"
    METRICS[GPU_UTIL]="$gpu_util"
    
    echo "  Name: $gpu_name"
    echo "  Mem:  $gpu_mem"
    echo "  Util: $gpu_util"
    echo "  Temp: $gpu_temp"
    echo ""
}

# [8/10] Temperature Metrics
collect_temperature_metrics() {
    log_info "[8/10] Collecting Temperature Metrics..."
    echo "[8/10] Collecting Temperature Metrics..."
    
    local temp="N/A"

    # Strategy 1: sensors (lm-sensors)
    if command -v sensors >/dev/null 2>&1; then
        local t=$(sensors | grep -E "Package id 0:|Core 0:" | head -1 | awk '{print $3}' | grep -o "[0-9.]*")
        [ -n "$t" ] && temp="${t}°C"
    fi

    # Strategy 2: /sys/class/thermal
    if [ "$temp" = "N/A" ] && ls /sys/class/thermal/thermal_zone*/temp >/dev/null 2>&1; then
         local t_milli=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
         if [ -n "$t_milli" ] && [ "$t_milli" -gt 0 ]; then
             local t_c=$(echo "scale=1; $t_milli / 1000" | bc)
             temp="${t_c}°C"
         fi
    fi
    
    # Strategy 3: Use GPU Temp as fallback if System Temp missing
    if [ "$temp" = "N/A" ] && [ "${METRICS[GPU_TEMP]}" != "N/A" ]; then
        temp="${METRICS[GPU_TEMP]} (GPU)"
    fi

    METRICS[TEMP]="$temp"
    echo "  Temp: $temp"
    echo ""
}

# [9/10] Top Processes
collect_top_processes() {
    log_info "[9/10] Collecting Top Processes..."
    echo "[9/10] Collecting Top Processes..."

    local output=""
    echo "  PID    USER     MEM%   COMMAND"
    echo "  ------------------------------"
    
    if ps aux --sort=-%mem >/dev/null 2>&1; then
        ps aux --sort=-%mem | head -6 | tail -5 | while read -r line; do
             local pid=$(echo "$line" | awk '{print $2}')
             local usr=$(echo "$line" | awk '{print $1}')
             local mem=$(echo "$line" | awk '{print $4}')
             local cmd=$(echo "$line" | awk '{print $11}')
             printf "  %-6s %-8s %-6s %s\n" "$pid" "$usr" "$mem" "$cmd"
             output="${output}${pid} ${usr} ${mem}% ${cmd};"
        done
    else
        ps aux -m | head -6 | tail -5 | while read -r line; do
             local pid=$(echo "$line" | awk '{print $2}')
             local usr=$(echo "$line" | awk '{print $1}')
             local mem=$(echo "$line" | awk '{print $4}')
             local cmd=$(echo "$line" | awk '{print $11}')
             printf "  %-6s %-8s %-6s %s\n" "$pid" "$usr" "$mem" "$cmd"
             output="${output}${pid} ${usr} ${mem}% ${cmd};"
        done
    fi
    
    METRICS[TOP_PROCS]="$output"
    echo ""
}

# [10/10] Check Alerts
check_alerts() {
    log_info "[10/10] Checking Alerts..."
    echo "[10/10] Checking Alerts..."
    
    local count=0
    local mem_usage=${METRICS[MEM_PERCENT]%.*}
    if [ -n "$mem_usage" ] && [ "$mem_usage" -gt 90 ]; then
        echo "  [ALERT] High Memory Usage: ${mem_usage}%"
        log_warn "High Memory Usage: ${mem_usage}%"
        ((count++))
    fi
    
    local disk_usage=${METRICS[DISK_PERCENT]%.*}
    if [ -n "$disk_usage" ] && [ "$disk_usage" -gt 90 ]; then
        echo "  [ALERT] High Disk Usage: ${disk_usage}%"
        log_warn "High Disk Usage: ${disk_usage}%"
        ((count++))
    fi
    
    [ $count -eq 0 ] && echo "  No alerts."
    echo ""
}

################################################################################
# Reporting
################################################################################

export_csv() {
    if [ ! -f "$CSV_FILE" ]; then
        echo "Timestamp,CPU_Model,CPU_Cores,CPU_Usage,Mem_Total,Mem_Used,Mem_Percent,Disk_Percent,Temp,GPU_Name" > "$CSV_FILE"
    fi
    echo "${TIMESTAMP},${METRICS[CPU_MODEL]},${METRICS[CPU_CORES]},${METRICS[CPU_USAGE]},${METRICS[MEM_TOTAL]},${METRICS[MEM_USED]},${METRICS[MEM_PERCENT]},${METRICS[DISK_PERCENT]},${METRICS[TEMP]},${METRICS[GPU_NAME]}" >> "$CSV_FILE"
}

generate_html() {
    cat > "$HTML_REPORT" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>System Report - $TIMESTAMP</title>
    <style>
        body { font-family: sans-serif; margin: 20px; background: #f0f2f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 2px solid #eee; padding-bottom: 10px; }
        .metric { margin-bottom: 15px; padding: 10px; background: #f9f9f9; border-radius: 4px; }
        .label { font-weight: bold; color: #555; }
        .value { color: #000; font-family: monospace; }
        .alert { color: red; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <h1>System Monitoring Report</h1>
        <p>Generated: $(date)</p>
        
        <div class="metric"><span class="label">CPU Model:</span> <span class="value">${METRICS[CPU_MODEL]}</span></div>
        <div class="metric"><span class="label">CPU Cores:</span> <span class="value">${METRICS[CPU_CORES]}</span></div>
        <div class="metric"><span class="label">CPU Usage:</span> <span class="value">${METRICS[CPU_USAGE]}%</span></div>
        
        <div class="metric"><span class="label">Memory:</span> <span class="value">${METRICS[MEM_USED]} / ${METRICS[MEM_TOTAL]} GB (${METRICS[MEM_PERCENT]}%)</span></div>
        
        <div class="metric"><span class="label">Disk:</span> <span class="value">${METRICS[DISK_USED]} used (${METRICS[DISK_PERCENT]}%)</span></div>
        
        <div class="metric"><span class="label">GPU:</span> <span class="value">${METRICS[GPU_NAME]} (${METRICS[GPU_MEM]})</span></div>
        
        <div class="metric"><span class="label">Temperature:</span> <span class="value">${METRICS[TEMP]}</span></div>
        
        <h3>Top Processes</h3>
        <pre>${METRICS[TOP_PROCS]//;/
}</pre>
    </div>
</body>
</html>
EOF
    log_info "Generated HTML report: $HTML_REPORT"
}

################################################################################
# Main
################################################################################

main() {
    setup_directories
    display_header
    
    collect_cpu_metrics
    collect_memory_metrics
    collect_disk_metrics
    collect_smart_status
    collect_network_metrics
    collect_load_metrics
    collect_gpu_metrics
    collect_temperature_metrics
    collect_top_processes
    check_alerts
    
    export_csv
    generate_html
    
    echo "Monitor Complete."
    echo "Report: $HTML_REPORT"
}

main
