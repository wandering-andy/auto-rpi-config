#!/bin/bash

## @module Network
## @brief Network configuration and DNS setup

## @fn network::configure
## @brief Configure network and DNS settings
network::configure() {
    log_step "Configuring network settings"
    network::configure_dns
    network::configure_wifi
}

## @fn network::configure_dns
## @brief Configure privacy-focused DNS
network::configure_dns() {
    log_info "Configuring privacy-focused DNS"
    cat > /etc/systemd/resolved.conf <<'EOF'
[Resolve]
DNS=9.9.9.9 84.200.69.80 1.1.1.1
DNSOverTLS=opportunistic
DNSSEC=allow-downgrade
Cache=yes
EOF

    systemctl restart systemd-resolved || true
    log_success "DNS configured with privacy-focused servers"
}

## @fn network::configure_wifi
## @brief Configure WiFi backup connection
network::configure_wifi() {
    if [[ -n "${CONFIG[wifi_ssid]:-}" ]]; then
        log_info "Configuring WiFi backup connection"
        cat > /etc/wpa_supplicant/wpa_supplicant.conf <<EOF
country=US
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
    ssid="${CONFIG[wifi_ssid]}"
    psk="${CONFIG[wifi_password]}"
    key_mgmt=WPA-PSK
}
EOF
        systemctl enable wpa_supplicant@wlan0.service || true
    else
        log_debug "No WiFi SSID provided; skipping WiFi configuration"
    fi
}