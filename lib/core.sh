#!/bin/bash
set -euo pipefail

## @module Core
## @brief Core functions for logging, validation, and YAML parsing
## @description Provides essential utilities used by all other modules

# Color codes for logging
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

## @fn log_step
## @brief Log a major configuration step
log_step() {
    printf '%b\n' "${BLUE}▶ $*${NC}" >&2
}

## @fn log_info
## @brief Log informational message
log_info() {
    printf '%b\n' "  ℹ $*" >&2
}

## @fn log_success
## @brief Log success message
log_success() {
    printf '%b\n' "${GREEN}  ✓ $*${NC}" >&2
}

## @fn log_warning
## @brief Log warning message
log_warning() {
    printf '%b\n' "${YELLOW}  ⚠ $*${NC}" >&2
}

## @fn log_error
## @brief Log error message
log_error() {
    printf '%b\n' "${RED}  ✗ ERROR: $*${NC}" >&2
}

## @fn core::install_yq
## @brief Install yq if missing (architecture-aware)
## @param version Optional yq version tag (default: v4.44.3)
core::install_yq() {
    local version="${1:-v4.44.3}"

    if command -v yq >/dev/null 2>&1; then
        return 0
    fi

    log_info "yq not found; installing version $version"

    local arch
    arch="$(uname -m)"
    local yq_asset=""

    case "$arch" in
        x86_64)  yq_asset="yq_linux_amd64" ;;
        aarch64) yq_asset="yq_linux_arm64" ;;
        armv7l)  yq_asset="yq_linux_arm" ;;
        armv6l)  yq_asset="yq_linux_arm" ;;
        *)
            log_error "Unsupported architecture '$arch' for yq install"
            return 1
            ;;
    esac

    local url="https://github.com/mikefarah/yq/releases/download/${version}/${yq_asset}"
    local dest="/usr/local/bin/yq"

    # Ensure curl is available
    if ! command -v curl >/dev/null 2>&1; then
        apt-get update -qq || { log_error "apt-get update failed"; return 1; }
        apt-get install -y curl ca-certificates || { log_error "Failed to install curl"; return 1; }
    fi

    # Download atomically
    local tmp
    tmp="$(mktemp)"
    if ! curl -fsSL "$url" -o "$tmp"; then
        log_error "Failed to download yq from $url"
        rm -f "$tmp"
        return 1
    fi

    if ! install -m 0755 "$tmp" "$dest"; then
        log_error "Failed to install yq to $dest"
        rm -f "$tmp"
        return 1
    fi
    rm -f "$tmp"

    if ! command -v yq >/dev/null 2>&1; then
        log_error "yq not found after installation"
        return 1
    fi

    log_success "yq installed successfully"
    return 0
}

## @fn core::get_config
## @brief Retrieve a config value from config.yml
## @param path YAML path (e.g., .hostname)
core::get_config() {
    local path="$1"
    yq -r "$path // \"\"" "config.yml" 2>/dev/null || echo ""
}

## @fn core::get_config_bool
## @brief Retrieve a boolean config value
## @param path YAML path
## @return "true" or "false"
core::get_config_bool() {
    local path="$1"
    local val
    val="$(yq -r "$path // \"false\"" "config.yml" 2>/dev/null || echo "false")"
    if [[ "$val" == "true" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

## @fn core::load_config
## @brief Load YAML configuration into CONFIG associative array
## @description Parses YAML file using yq and populates global CONFIG array
## @param config_file Path to YAML configuration file (default: config.yml)
## @return 0 on success, 1 on failure
## @example core::load_config "my-config.yml"
core::load_config() {
    local config_file="${1:-config.yml}"
    
    log_step "Loading configuration from: ${config_file}"
    
    # Ensure yq is available
    core::install_yq || return 1
    
    # Validate file exists and is readable
    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: ${config_file}"
        return 1
    fi
    
    if [[ ! -r "$config_file" ]]; then
        log_error "Configuration file not readable: ${config_file}"
        return 1
    fi
    
    # Validate YAML syntax
    if ! yq eval '.' "$config_file" >/dev/null 2>&1; then
        log_error "Invalid YAML syntax in: ${config_file}"
        return 1
    fi
    
    # Declare CONFIG as associative array if not already
    if ! declare -p CONFIG &>/dev/null; then
        declare -gA CONFIG
    fi

    # Load common config values
    CONFIG[hostname]="$(core::get_config '.hostname')"
    CONFIG[username]="$(core::get_config '.username')"
    CONFIG[timezone]="$(core::get_config '.timezone')"
    CONFIG[locale]="$(core::get_config '.locale')"
    CONFIG[container_runtime]="$(core::get_config '.container_runtime')"
    CONFIG[nvme_enable]="$(core::get_config_bool '.nvme_enable')"
    CONFIG[install_tailscale]="$(core::get_config_bool '.install_tailscale')"
    CONFIG[install_k3s]="$(core::get_config_bool '.install_k3s')"
    CONFIG[install_node_exporter]="$(core::get_config_bool '.install_node_exporter')"
    CONFIG[enable_desktop]="$(core::get_config_bool '.enable_desktop')"
    CONFIG[3dprinter_services]="$(core::get_config '.3dprinter_services')"
    CONFIG[3dprinter_force_reconfigure]="$(core::get_config_bool '.3dprinter_force_reconfigure')"
    CONFIG[3dprinter_kiauh_repo]="$(core::get_config '.3dprinter_kiauh_repo')"
    CONFIG[3dprinter_kiauh_path]="$(core::get_config '.3dprinter_kiauh_path')"
    CONFIG[ssh_public_key]="$(core::get_config '.ssh_public_key')"

    log_success "Configuration loaded successfully from ${config_file}"
}

## @fn core::validate_environment
## @brief Check prerequisites (root, network, disk space)
core::validate_environment() {
    log_step "Validating environment"

    # Check root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        return 1
    fi

    # Check network
    if ! ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        log_warning "No internet connectivity detected"
    fi

    # Check disk space (require at least 1GB free)
    local avail_kb
    avail_kb="$(df / --output=avail | tail -1 | tr -d ' ')"
    if [[ $avail_kb -lt 1048576 ]]; then
        log_error "Insufficient disk space (need 1GB+, have $(($avail_kb / 1024))MB)"
        return 1
    fi

    log_success "Environment validation passed"
    return 0
}