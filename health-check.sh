#!/bin/bash
set -euo pipefail

## @script Health Check
## @brief System health monitoring with color-coded output
## @description Checks disk, memory, CPU, temperature, and services

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

## @fn check_disk_usage
## @brief Check disk usage with color coding
## @output Color-coded disk usage percentage
check_disk_usage() {
    local usage
    if ! usage=$(df / --output=pcent 2>/dev/null | tail -1 | tr -d '% '); then
        printf '%b\n' "${YELLOW}⚠ Disk: Unable to check${NC}"
        return 0
    fi
    
    if [ "$usage" -le 25 ]; then
        printf '%b\n' "${GREEN}✓ Disk: ${usage}%${NC}"
    elif [ "$usage" -le 74 ]; then
        printf '%b\n' "${YELLOW}⚠ Disk: ${usage}%${NC}"
    else
        printf '%b\n' "${RED}✗ Disk: ${usage}%${NC}"
    fi
}

## @fn check_temperature
## @brief Check CPU temperature in Fahrenheit with color coding
## @output Color-coded temperature in Fahrenheit
check_temperature() {
    if ! command -v vcgencmd &>/dev/null; then
        printf '%b\n' "${BLUE}ℹ Temp: vcgencmd not available${NC}"
        return 0
    fi
    
    local temp_c temp_f
    if ! temp_c=$(vcgencmd measure_temp 2>/dev/null | cut -d= -f2 | cut -d\' -f1); then
        printf '%b\n' "${YELLOW}⚠ Temp: Unable to read${NC}"
        return 0
    fi
    
    # Validate temperature is numeric
    if ! [[ "$temp_c" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        printf '%b\n' "${YELLOW}⚠ Temp: Invalid reading${NC}"
        return 0
    fi
    
    temp_f=$(awk "BEGIN {printf \"%.1f\", ($temp_c * 9/5) + 32}")
    
    if awk "BEGIN {exit !($temp_f < 120)}"; then
        printf '%b\n' "${GREEN}✓ Temp: ${temp_f}°F${NC}"
    elif awk "BEGIN {exit !($temp_f < 140)}"; then
        printf '%b\n' "${YELLOW}⚠ Temp: ${temp_f}°F${NC}"
    else
        printf '%b\n' "${RED}✗ Temp: ${temp_f}°F${NC}"
    fi
}

## @fn check_nvme_health
## @brief Check NVMe drive health and temperature
## @output Color-coded NVMe health status
check_nvme_health() {
    if [[ ! -e "/dev/nvme0" ]]; then
        printf '%b\n' "${BLUE}ℹ NVMe: Not detected${NC}"
        return 0
    fi
    
    if ! command -v nvme &>/dev/null; then
        printf '%b\n' "${BLUE}ℹ NVMe: nvme-cli not installed${NC}"
        return 0
    fi
    
    local temp avail_spare percent_used
    if ! temp=$(nvme smart-log /dev/nvme0 2>/dev/null | grep "temperature" | head -1 | awk '{print $3}'); then
        printf '%b\n' "${BLUE}ℹ NVMe: Health data unavailable${NC}"
        return 0
    fi
    
    avail_spare=$(nvme smart-log /dev/nvme0 2>/dev/null | grep "available_spare" | awk '{print $3}' | tr -d '%' || echo "100")
    percent_used=$(nvme smart-log /dev/nvme0 2>/dev/null | grep "percentage_used" | awk '{print $3}' | tr -d '%' || echo "0")

    # Validate all values are numeric
    if [[ "$temp" =~ ^[0-9]+$ ]] && [[ "$avail_spare" =~ ^[0-9]+$ ]] && [[ "$percent_used" =~ ^[0-9]+$ ]]; then
        if [[ $temp -le 60 ]]; then
            printf '%b\n' "${GREEN}✓ NVMe Temp: ${temp}°C${NC}"
        elif [[ $temp -le 70 ]]; then
            printf '%b\n' "${YELLOW}⚠ NVMe Temp: ${temp}°C${NC}"
        else
            printf '%b\n' "${RED}✗ NVMe Temp: ${temp}°C${NC}"
        fi

        if [[ $avail_spare -ge 90 ]]; then
            printf '%b\n' "${GREEN}✓ NVMe Spare: ${avail_spare}%${NC}"
        elif [[ $avail_spare -ge 80 ]]; then
            printf '%b\n' "${YELLOW}⚠ NVMe Spare: ${avail_spare}%${NC}"
        else
            printf '%b\n' "${RED}✗ NVMe Spare: ${avail_spare}%${NC}"
        fi

        if [[ $percent_used -le 50 ]]; then
            printf '%b\n' "${GREEN}✓ NVMe Used: ${percent_used}%${NC}"
        elif [[ $percent_used -le 80 ]]; then
            printf '%b\n' "${YELLOW}⚠ NVMe Used: ${percent_used}%${NC}"
        else
            printf '%b\n' "${RED}✗ NVMe Used: ${percent_used}%${NC}"
        fi
    else
        printf '%b\n' "${BLUE}ℹ NVMe: Health data unavailable${NC}"
    fi
}

## @fn check_services
## @brief Check essential service status
## @output Color-coded service status
check_services() {
    local services=("docker" "tailscaled" "node_exporter")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            printf '%b\n' "${GREEN}✓ $service: RUNNING${NC}"
        elif systemctl list-unit-files "${service}.service" &>/dev/null; then
            printf '%b\n' "${RED}✗ $service: NOT RUNNING${NC}"
        else
            printf '%b\n' "${BLUE}ℹ $service: Not installed${NC}"
        fi
    done
}

main() {
    printf '%b\n' "=== System Health Check ==="
    printf '%b\n' "Timestamp: $(date)"
    printf '\n'
    check_disk_usage
    check_temperature
    check_nvme_health
    printf '\n'
    printf '%b\n' "--- Service Status ---"
    check_services
    printf '\n=== Health Check Complete ===\n'
}

main "$@"
