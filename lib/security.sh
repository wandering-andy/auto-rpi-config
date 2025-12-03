#!/bin/bash

## @module Security
## @brief Security hardening and automatic updates

## @fn security::configure
## @brief Configure security settings
security::configure() {
    log_step "Configuring security settings"
    security::configure_auto_updates
    security::disable_services
}

## @fn security::configure_auto_updates
## @brief Enable automatic security updates
security::configure_auto_updates() {
    if [[ "${CONFIG[enable_auto_updates]:-true}" == "true" ]]; then
        log_info "Configuring automatic security updates"
        apt-get update
        apt-get install -y --no-install-recommends unattended-upgrades
        dpkg-reconfigure -plow unattended-upgrades || true
        echo 'Unattended-Upgrade::Automatic-Reboot "false";' >> /etc/apt/apt.conf.d/50unattended-upgrades || true
        log_success "Automatic security updates configured"
    else
        log_debug "Automatic updates disabled by config"
    fi
}

## @fn security::disable_services
## @brief Disable unnecessary services
security::disable_services() {
    if [[ "${CONFIG[disable_unnecessary_services]:-false}" == "true" ]]; then
        log_info "Disabling unnecessary services"
        systemctl disable bluetooth.service || true
        systemctl disable avahi-daemon.service || true
        log_success "Unnecessary services disabled"
    fi
}