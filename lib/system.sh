#!/bin/bash

## @module System
## @brief System configuration and basic setup

## @fn system::configure
## @brief Configure system settings
system::configure() {
    log_step "Configuring system settings"

    system::configure_hostname
    system::create_user
    system::configure_sudo
    system::configure_timezone
    system::configure_keyboard
    system::configure_locale
    system::update_system
}

## @fn system::configure_hostname
## @brief Set system hostname
system::configure_hostname() {
    log_info "Setting hostname to ${CONFIG[hostname]}"

    local current_hostname
    current_hostname=$(cat /etc/hostname)
    sed -i "s/127.0.1.1.*$current_hostname/127.0.1.1\t${CONFIG[hostname]}/g" /etc/hosts
    echo "${CONFIG[hostname]}" > /etc/hostname
    hostnamectl set-hostname "${CONFIG[hostname]}"

    log_success "Hostname set to ${CONFIG[hostname]}"
}

## @fn system::create_user
## @brief Create primary user account
system::create_user() {
    log_info "Creating user: ${CONFIG[username]}"

    useradd -m -G sudo -s /bin/bash "${CONFIG[username]}" || true
    echo "${CONFIG[username]}:${CONFIG[user_password]}" | chpasswd

    log_success "User ${CONFIG[username]} created"
}

## @fn system::configure_sudo
## @brief Configure passwordless sudo
system::configure_sudo() {
    log_info "Configuring passwordless sudo"

    echo "${CONFIG[username]} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/010_"${CONFIG[username]}"-nopasswd
    chmod 440 /etc/sudoers.d/010_"${CONFIG[username]}"-nopasswd

    log_success "Passwordless sudo configured for ${CONFIG[username]}"
}

## @fn system::configure_timezone
## @brief Set system timezone
system::configure_timezone() {
    log_info "Setting timezone to ${CONFIG[timezone]}"
    timedatectl set-timezone "${CONFIG[timezone]}"
    log_success "Timezone set to ${CONFIG[timezone]}"
}

## @fn system::configure_keyboard
## @brief Set keyboard layout
system::configure_keyboard() {
    log_info "Setting keyboard layout to ${CONFIG[keyboard_layout]}"
    sed -i "s/XKBLAYOUT=.*/XKBLAYOUT=\"${CONFIG[keyboard_layout]}\"/" /etc/default/keyboard
    log_success "Keyboard layout set to ${CONFIG[keyboard_layout]}"
}

## @fn system::configure_locale
## @brief Set system locale
system::configure_locale() {
    log_info "Setting locale to ${CONFIG[locale]}"
    sed -i "s/^# ${CONFIG[locale]}/${CONFIG[locale]}/" /etc/locale.gen
    locale-gen
    update-locale LANG="${CONFIG[locale]}"
    log_success "Locale set to ${CONFIG[locale]}"
}

## @fn system::update_system
## @brief Update system packages
system::update_system() {
    log_info "Updating system packages"
    apt-get update
    apt-get full-upgrade -y
    log_success "System packages updated"
}