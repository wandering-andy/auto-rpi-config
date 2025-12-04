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

    # Pre-pull any extra images user requested (comma-separated list)
    containers::pre_pull_extra || log_info "No extra containers to pre-pull or pre-pull failed"

    containers::install_tailscale || true

    if [[ "${CONFIG[install_k3s]:-false}" == "true" ]]; then
        containers::install_k3s || true
    else
        log_info "K3s installation disabled by configuration"
    fi
}

## Choose which runtime to use for pulling: podman preferred when both present
containers::choose_pull_runtime() {
    local cfg_runtime="${CONFIG[container_runtime]:-podman}"
    cfg_runtime="$(tr '[:upper:]' '[:lower:]' <<<"$cfg_runtime")"

    # If user explicitly set 'none', nothing to do
    if [[ "$cfg_runtime" == "none" ]]; then
        echo ""
        return 0
    fi

    local has_podman=0 has_docker=0
    if command -v podman >/dev/null 2>&1; then has_podman=1; fi
    if command -v docker >/dev/null 2>&1; then has_docker=1; fi

    if [[ "$has_podman" -eq 1 && "$has_docker" -eq 1 ]]; then
        # both present -> prefer podman
        echo "podman"
    elif [[ "$has_podman" -eq 1 ]]; then
        echo "podman"
    elif [[ "$has_docker" -eq 1 ]]; then
        echo "docker"
    else
        echo ""
    fi
}

## Pull an image with the chosen runtime
containers::pull_image() {
    local runtime="$1"
    local image="$2"

    if [[ -z "$runtime" ]]; then
        log_warning "No container runtime available to pull $image"
        return 1
    fi

    log_info "Pre-pulling image with $runtime: $image"
    if [[ "$runtime" == "podman" ]]; then
        podman pull "$image" && log_success "Pulled $image via podman" || { log_warning "Failed to pull $image with podman"; return 1; }
    else
        docker pull "$image" && log_success "Pulled $image via docker" || { log_warning "Failed to pull $image with docker"; return 1; }
    fi
}

## Read CONFIG[extra_containers] and pre-pull images
containers::pre_pull_extra() {
    local list="${CONFIG[extra_containers]:-}"
    if [[ -z "${list//[[:space:]]/}" ]]; then
        return 0
    fi

    local runtime
    runtime="$(containers::choose_pull_runtime)"
    if [[ -z "$runtime" ]]; then
        log_warning "No container runtime available for pre-pulling extra containers"
        return 1
    fi

    IFS=',' read -ra images <<<"$list"
    for img in "${images[@]}"; do
        img="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' <<<"$img")"
        [[ -z "$img" ]] && continue
        containers::pull_image "$runtime" "$img" || log_warning "Pre-pull failed for $img"
    done
    return 0
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