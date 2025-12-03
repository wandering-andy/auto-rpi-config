#!/bin/bash

## @module NVMe
## @brief NVMe-specific performance and health optimizations

## @fn nvme::configure
## @brief Configure NVMe performance settings
nvme::configure() {
    log_step "Configuring NVMe optimizations"

    if [[ "${CONFIG[nvme_enable]:-true}" != "true" ]]; then
        log_info "NVMe optimizations disabled by configuration"
        return 0
    fi

    if [[ ! -e "/dev/nvme0" ]]; then
        log_warning "NVMe device not detected, skipping optimizations"
        return 0
    fi

    nvme::install_tools
    nvme::configure_io_scheduler
    nvme::configure_mount_options
    nvme::enable_trim
    nvme::configure_power_management
}

## @fn nvme::install_tools
## @brief Install NVMe management tools
nvme::install_tools() {
    log_info "Installing NVMe tools"
    apt-get update
    apt-get install -y --no-install-recommends nvme-cli smartmontools
}

## @fn nvme::configure_io_scheduler
## @brief Set optimal I/O scheduler for NVMe
nvme::configure_io_scheduler() {
    log_info "Configuring I/O scheduler for NVMe"

    local nvme_devices
    nvme_devices=$(lsblk -d -o NAME | grep -E '^nvme' || true)
    while IFS= read -r device; do
        if [[ -w "/sys/block/${device}/queue/scheduler" ]]; then
            echo "none" > "/sys/block/${device}/queue/scheduler"
            log_debug "Set I/O scheduler to none for ${device}"
        fi
    done <<<"$nvme_devices"

    cat > /etc/udev/rules.d/60-nvme-scheduler.rules <<'EOF'
# Set I/O scheduler to none for NVMe devices
ACTION=="add|change", KERNEL=="nvme*", ATTR{queue/scheduler}="none"
EOF

    core::mark_reboot_required
}

## @fn nvme::configure_mount_options
## @brief Set optimal mount options for NVMe
nvme::configure_mount_options() {
    log_info "Configuring NVMe mount options"

    if grep -q " / " /etc/fstab; then
        cp /etc/fstab "/etc/fstab.backup.$(date +%Y%m%d)" || true

        if mount | grep -q " / .*nvme"; then
            sed -i 's|\(.*\s/\s*\w*\s*\)defaults|\1defaults,noatime,nodiratime|' /etc/fstab
            log_info "Added noatime,nodiratime to root mount options"
        fi
    fi
}

## @fn nvme::enable_trim
## @brief Enable and schedule TRIM for NVMe
nvme::enable_trim() {
    log_info "Enabling TRIM support"

    if mount | grep -q " / .*nvme"; then
        sed -i 's|\(.*\s/\s*\w*\s*\)defaults|\1defaults,discard|' /etc/fstab || true
        log_info "Added discard option to root mount"
    fi

    systemctl enable --now fstrim.timer || true
    log_success "TRIM enabled and scheduled"
}

## @fn nvme::configure_power_management
## @brief Configure NVMe power management
nvme::configure_power_management() {
    log_info "Configuring NVMe power management"

    local nvme_devices
    nvme_devices=$(lsblk -d -o NAME | grep -E '^nvme' || true)
    while IFS= read -r device; do
        if [[ -w "/sys/block/${device}/device/device/power/control" ]]; then
            echo "performance" > "/sys/block/${device}/device/device/power/control"
        fi
    done <<<"$nvme_devices"

    cat > /etc/udev/rules.d/61-nvme-power.rules <<'EOF'
# Set NVMe power management for performance
ACTION=="add|change", KERNEL=="nvme*", SUBSYSTEM=="pci", ATTR{power/control}="performance"
EOF

    core::mark_reboot_required
}