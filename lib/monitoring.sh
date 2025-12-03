#!/bin/bash

## @module Monitoring
## @brief System monitoring and health checks

## @fn monitoring::configure
## @brief Configure monitoring
monitoring::configure() {
    log_step "Configuring monitoring"

    if [[ "${CONFIG[install_node_exporter]:-true}" == "true" ]]; then
        monitoring::install_node_exporter
    fi

    monitoring::schedule_health_checks
}

## @fn monitoring::install_node_exporter
## @brief Install Prometheus Node Exporter
monitoring::install_node_exporter() {
    log_info "Installing Prometheus Node Exporter"
    useradd -rs /bin/false node_exporter || true

    local latest_info
    latest_info=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest || echo "")
    local download_url
    download_url=$(echo "$latest_info" | grep "browser_download_url.*linux-arm64.tar.gz" | head -1 | cut -d '"' -f 4 || true)

    if [[ -z "$download_url" ]]; then
        log_warning "Could not find Node Exporter download URL; attempting package install"
        apt-get update && apt-get install -y --no-install-recommends prometheus-node-exporter || log_warning "Node exporter package not available"
        return
    fi

    local package_name extract_dir
    package_name=$(basename "$download_url")
    wget "$download_url" -O "$package_name"
    tar -xzf "$package_name"
    extract_dir=$(tar -tzf "$package_name" | head -1 | cut -f1 -d"/")
    cp "$extract_dir/node_exporter" /usr/local/bin/
    chown node_exporter:node_exporter /usr/local/bin/node_exporter

    cat > /etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter --web.listen-address=:${CONFIG[node_exporter_port]:-9100}

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now node_exporter || true

    rm -rf "$package_name" "$extract_dir" || true
    log_success "Node Exporter installed and running on port ${CONFIG[node_exporter_port]:-9100}"
}

## @fn monitoring::schedule_health_checks
## @brief Schedule automatic health checks
monitoring::schedule_health_checks() {
    log_info "Scheduling health checks"

    cp health-check.sh /usr/local/bin/health-check.sh || true
    chmod +x /usr/local/bin/health-check.sh || true

    cat > /etc/systemd/system/health-check.service <<EOF
[Unit]
Description=System Health Check
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/health-check.sh
User=root
EOF

    cat > /etc/systemd/system/health-check.timer <<EOF
[Unit]
Description=Run health check every 15 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=${CONFIG[health_check_interval]:-900}s
RandomizedDelaySec=30

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now health-check.timer || true
    log_success "Health checks scheduled"
}