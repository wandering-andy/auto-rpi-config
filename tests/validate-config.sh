#!/bin/bash
set -euo pipefail

## @script Config Validator
## @brief Validates YAML configuration files
## @description Checks YAML syntax and required fields for auto-rpi-config

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Accept config file as argument (default to config.yml.example)
CONFIG_FILE="${1:-config.yml.example}"

## @fn error
## @brief Print error message and exit
error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

## @fn warning
## @brief Print warning message
warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

## @fn success
## @brief Print success message
success() {
    echo -e "${GREEN}✓ $1${NC}"
}

## @fn check_file_exists
## @brief Verify config file exists
check_file_exists() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "Configuration file not found: ${CONFIG_FILE}"
    fi
    success "Configuration file exists: ${CONFIG_FILE}"
}

## @fn check_yq_available
## @brief Ensure yq is available for YAML parsing
check_yq_available() {
    if ! command -v yq >/dev/null 2>&1; then
        warning "yq not found, installing..."
        
        # Determine architecture
        local arch
        arch="$(uname -m)"
        local yq_binary="yq_linux_amd64"
        
        case "$arch" in
            x86_64) yq_binary="yq_linux_amd64" ;;
            aarch64|arm64) yq_binary="yq_linux_arm64" ;;
            armv7l) yq_binary="yq_linux_arm" ;;
            *) error "Unsupported architecture: $arch" ;;
        esac
        
        # Download yq
        local yq_url="https://github.com/mikefarah/yq/releases/latest/download/${yq_binary}"
        curl -sL "$yq_url" -o /tmp/yq || error "Failed to download yq"
        chmod +x /tmp/yq
        
        # Use /tmp/yq for validation
        export PATH="/tmp:$PATH"
    fi
    success "yq is available"
}

## @fn validate_yaml_syntax
## @brief Check if file is valid YAML
validate_yaml_syntax() {
    echo "Validating YAML syntax..."
    
    if ! yq eval '.' "$CONFIG_FILE" >/dev/null 2>&1; then
        error "Invalid YAML syntax in ${CONFIG_FILE}"
    fi
    
    success "YAML syntax is valid"
}

## @fn validate_required_fields
## @brief Check that required configuration fields exist
validate_required_fields() {
    echo "Validating required fields..."
    
    local required_fields=(
        "hostname"
        "username"
        "timezone"
        "locale"
    )
    
    local missing_fields=()
    
    for field in "${required_fields[@]}"; do
        local value
        value="$(yq eval ".${field}" "$CONFIG_FILE" 2>/dev/null || echo "null")"
        
        if [[ "$value" == "null" || -z "$value" ]]; then
            missing_fields+=("$field")
        fi
    done
    
    if [[ ${#missing_fields[@]} -gt 0 ]]; then
        error "Missing required fields: ${missing_fields[*]}"
    fi
    
    success "All required fields present"
}

## @fn validate_hostname
## @brief Validate hostname format
validate_hostname() {
    local hostname
    hostname="$(yq eval '.hostname' "$CONFIG_FILE")"
    
    # RFC 1123 hostname validation (simplified)
    if [[ ! "$hostname" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
        error "Invalid hostname format: ${hostname} (must be lowercase alphanumeric with hyphens)"
    fi
    
    success "Hostname format is valid: ${hostname}"
}

## @fn validate_container_runtime
## @brief Validate container_runtime value
validate_container_runtime() {
    local runtime
    runtime="$(yq eval '.container_runtime // "podman"' "$CONFIG_FILE")"
    
    case "$runtime" in
        none|podman|docker|both)
            success "Container runtime is valid: ${runtime}"
            ;;
        *)
            error "Invalid container_runtime: ${runtime} (must be: none, podman, docker, or both)"
            ;;
    esac
}

## @fn validate_boolean_fields
## @brief Validate boolean configuration fields
validate_boolean_fields() {
    local bool_fields=(
        "nvme_enable"
        "install_tailscale"
        "enable_auto_updates"
        "enable_desktop"
        "auto_reboot"
    )
    
    for field in "${bool_fields[@]}"; do
        local value
        value="$(yq eval ".${field} // \"null\"" "$CONFIG_FILE")"
        
        # Skip if field doesn't exist (optional fields)
        [[ "$value" == "null" ]] && continue
        
        if [[ "$value" != "true" && "$value" != "false" ]]; then
            warning "Field '${field}' should be true or false, got: ${value}"
        fi
    done
    
    success "Boolean fields are valid"
}

## @fn validate_3dprinter_services
## @brief Validate 3D printer services format
validate_3dprinter_services() {
    local services
    services="$(yq eval '.3dprinter_services // ""' "$CONFIG_FILE")"

    # Skip if empty (module won't run)
    [[ -z "$services" ]] && return 0

    # Valid service names (explicit array for exact-match checks)
    local -a valid_services=("octoprint" "octoklipper" "orcaslicer" "manyfold" "fluidd")

    IFS=',' read -ra service_list <<<"$services"
    for service in "${service_list[@]}"; do
        # Trim whitespace (portable)
        service="$(echo "$service" | xargs)"

        local found=false
        for v in "${valid_services[@]}"; do
            if [[ "$service" == "$v" ]]; then
                found=true
                break
            fi
        done

        if [[ "$found" == "false" ]]; then
            warning "Unknown 3D printer service: ${service}"
        fi
    done

    success "3D printer services are valid"
}

## @fn validate_network_config
## @brief Validate network configuration
validate_network_config() {
    local wifi_ssid
    local wifi_password
    
    wifi_ssid="$(yq eval '.wifi_ssid // ""' "$CONFIG_FILE")"
    wifi_password="$(yq eval '.wifi_password // ""' "$CONFIG_FILE")"
    
    # If one is set, both should be set
    if [[ -n "$wifi_ssid" && -z "$wifi_password" ]]; then
        warning "wifi_ssid is set but wifi_password is empty"
    elif [[ -z "$wifi_ssid" && -n "$wifi_password" ]]; then
        warning "wifi_password is set but wifi_ssid is empty"
    fi
    
    success "Network configuration is valid"
}

## @fn validate_security
## @brief Check for potential security issues
validate_security() {
    local password
    password="$(yq eval '.user_password // ""' "$CONFIG_FILE")"
    
    # Warn about default/weak passwords
    if [[ "$password" == "changeme"* ]] || [[ "$password" == "password" ]]; then
        warning "Weak or default password detected. Please use a strong password!"
    fi
    
    # Check if this is the example file with secrets
    if [[ "$CONFIG_FILE" == *"example"* ]]; then
        local has_secrets=false
        
        [[ -n "$(yq eval '.wifi_password // ""' "$CONFIG_FILE")" ]] && has_secrets=true
        [[ -n "$(yq eval '.tailscale_authkey // ""' "$CONFIG_FILE")" ]] && has_secrets=true
        
        if [[ "$has_secrets" == "true" ]]; then
            warning "Example file contains secrets - ensure actual config.yml is in .gitignore"
        fi
    fi
    
    success "Security checks passed"
}

## @fn main
## @brief Main validation workflow
main() {
    echo "=================================================="
    echo "auto-rpi-config Configuration Validator"
    echo "=================================================="
    echo "Validating: ${CONFIG_FILE}"
    echo
    
    check_file_exists
    check_yq_available
    validate_yaml_syntax
    validate_required_fields
    validate_hostname
    validate_container_runtime
    validate_boolean_fields
    validate_3dprinter_services
    validate_network_config
    validate_security
    
    echo
    echo "=================================================="
    success "Configuration file is valid!"
    echo "=================================================="
    echo
    echo "To run configuration:"
    echo "  sudo ./auto-rpi-config.sh ${CONFIG_FILE}"
    echo
}

main "$@"
