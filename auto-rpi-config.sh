#!/bin/bash
set -euo pipefail

## @script Raspberry Pi Auto-Configuration
## @brief Main orchestrator for automated Raspberry Pi configuration
## @description Idempotent configuration system for Raspberry Pi OS Lite (Debian Trixie)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/core.sh
source "${SCRIPT_DIR}/lib/core.sh"

reboot_if_required() {
    if [[ -f "/var/run/reboot-required" ]] || [[ "${REBOOT_REQUIRED:-false}" == "true" ]]; then
        log_step "System requires reboot - rebooting immediately"
        sync
        reboot
        exit 0
    fi
}

# Configuration file (default to config.yml, allow override via argument)
readonly CONFIG_FILE="${1:-config.yml}"

main() {
    log_step "Starting Raspberry Pi configuration"
    log_info "Using configuration file: ${CONFIG_FILE}"
    
    # Validate configuration file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: ${CONFIG_FILE}"
        echo "Usage: $0 [config-file.yml]"
        echo "Example: $0 config.yml"
        echo "Example: $0 /path/to/my-pi-config.yml"
        exit 1
    fi
    
    # Load configuration
    core::load_config "$CONFIG_FILE" || {
        log_error "Failed to load configuration from ${CONFIG_FILE}"
        exit 1
    }

    log_step "Executing configuration modules"

    # System (always)
    # shellcheck source=lib/system.sh
    source "${SCRIPT_DIR}/lib/system.sh"
    system::configure

    # NVMe (toggle: nvme_enable)
    if [[ "${CONFIG[nvme_enable]:-false}" == "true" ]]; then
        # shellcheck source=lib/nvme.sh
        source "${SCRIPT_DIR}/lib/nvme.sh"
        nvme::configure
    else
        log_info "Skipping module: nvme (nvme_enable=false)"
    fi

    # Network (always; module should no-op if not configured)
    # shellcheck source=lib/network.sh
    source "${SCRIPT_DIR}/lib/network.sh"
    network::configure

    # Security (always)
    # shellcheck source=lib/security.sh
    source "${SCRIPT_DIR}/lib/security.sh"
    security::configure

    # Desktop (toggle: enable_desktop)
    if [[ "${CONFIG[enable_desktop]:-false}" == "true" ]]; then
        # shellcheck source=lib/desktop.sh
        source "${SCRIPT_DIR}/lib/desktop.sh"
        desktop::configure
    else
        log_info "Skipping module: desktop (enable_desktop=false)"
    fi

    # Development (no explicit toggle; keep always to preserve prior behavior)
    # shellcheck source=lib/development.sh
    source "${SCRIPT_DIR}/lib/development.sh"
    development::configure

    # Containers (container_runtime: none|podman|docker|both)
    rt="${CONFIG[container_runtime]:-none}"
    if [[ "$rt" == "none" ]]; then
        log_info "Skipping module: containers (container_runtime=none)"
    else
        # shellcheck source=lib/containers.sh
        source "${SCRIPT_DIR}/lib/containers.sh"
        containers::configure
    fi

    # 3D printer (enabled when list is non-empty)
    services="${CONFIG[3dprinter_services]:-}"
    if [[ -n "${services//[[:space:]]/}" ]]; then
        # shellcheck source=lib/3dprinter.sh
        source "${SCRIPT_DIR}/lib/3dprinter.sh"
        3dprinter::configure
    else
        log_info "Skipping module: 3dprinter (no services configured)"
    fi

    # Monitoring (toggle: install_node_exporter)
    if [[ "${CONFIG[install_node_exporter]:-false}" == "true" ]]; then
        # shellcheck source=lib/monitoring.sh
        source "${SCRIPT_DIR}/lib/monitoring.sh"
        monitoring::configure
    else
        log_info "Skipping module: monitoring (install_node_exporter=false)"
    fi

    core::cleanup
    reboot_if_required
    log_success "Configuration completed successfully"
}

main "$@"