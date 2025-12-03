#!/bin/bash

## @module Containers
## @brief Container runtime and orchestration setup

## @fn containers::configure
## @brief Install and configure container tools
containers::configure() {
    log_step "Configuring container environment"

    local runtime="${CONFIG[container_runtime]:-podman}"
    runtime="$(tr '[:upper:]' '[:lower:]' <<<"$runtime")"

    case "$runtime" in
        none | '' | '0')
            log_info "Container runtimes disabled by configuration"
            ;;
        podman)
            containers::install_podman
            ;;
        docker)
            containers::install_docker
            ;;
        both)
            containers::install_podman
            containers::install_docker
            ;;
        *)
            log_warning "Unknown container_runtime='$runtime' - defaulting to podman"
            containers::install_podman
            ;;
    esac

    containers::install_tailscale || true

    if [[ "${CONFIG[install_k3s]:-false}" == "true" ]]; then
        containers::install_k3s || true
    else
        log_info "K3s installation disabled by configuration"
    fi
}

## @fn containers::install_podman
## @brief Install Podman and helpers
containers::install_podman() {
    if command -v podman >/dev/null 2>&1; then
        log_info "Podman already installed"
        return 0
    fi
    log_info "Installing Podman and helpers"
    apt-get update
    apt-get install -y --no-install-recommends podman fuse-overlayfs slirp4netns
    log_success "Podman installed"
}

## @fn containers::install_docker
## @brief Install Docker
containers::install_docker() {
    if command -v docker >/dev/null 2>&1; then
        log_info "Docker already installed"
        return 0
    fi
    log_info "Installing Docker (docker.io)"
    apt-get update
    apt-get install -y --no-install-recommends docker.io
    systemctl enable --now docker || true
    log_success "Docker installed"
}

## @fn containers::install_k3s
## @brief Install K3s with cgroups configuration
containers::install_k3s() {
    if [[ -n "${CONFIG[k3s_server]:-}" && -n "${CONFIG[k3s_token]:-}" ]]; then
        log_info "Installing K3s as ${CONFIG[k3s_role]:-agent} node"
        if [[ -f /boot/firmware/cmdline.txt ]]; then
            if ! grep -q "cgroup_memory=1" /boot/firmware/cmdline.txt; then
                sed -i 's/$/ cgroup_memory=1 cgroup_enable=memory/' /boot/firmware/cmdline.txt
                core::mark_reboot_required
            fi
        fi

        curl -sfL https://get.k3s.io | \
            K3S_URL="${CONFIG[k3s_server]}" \
            K3S_TOKEN="${CONFIG[k3s_token]}" \
            sh -s - agent
    else
        log_warning "K3s install requested but k3s_server/k3s_token not provided"
    fi
}

## @fn containers::install_tailscale
## @brief Install Tailscale if requested
containers::install_tailscale() {
    if [[ "${CONFIG[install_tailscale]:-}" == "true" ]]; then
        if command -v tailscale >/dev/null 2>&1; then
            log_info "Tailscale already installed"
            return 0
        fi
        log_info "Installing Tailscale"
        curl -fsSL https://tailscale.com/install.sh | sh || log_warning "Tailscale install script failed"
    fi
}