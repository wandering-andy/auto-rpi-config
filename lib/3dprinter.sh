#!/bin/bash
set -euo pipefail

## @module 3D Printer Services
## @brief Container-based 3D printing services and KIAUH installer
## @description Deploys OctoPrint, Klipper, OrcaSlicer, Manyfold via containers, or clones KIAUH for Fluidd
## @version 1.0.0
## @since 2024-01-01
## @warning Requires container runtime (podman/docker) for container-backed services
## @note Fluidd is installed via KIAUH and does not require a container runtime
## @see https://github.com/dw-0/kiauh for KIAUH documentation
## @example 3dprinter_services: "octoprint,fluidd"

3dprinter::configure() {
    log_step "Configuring 3D printer services"

    local services="${CONFIG[3dprinter_services]:-}"  # Comma-separated list of services
    if [[ -z "$services" ]]; then
        log_info "No 3D printer services requested; skipping 3dprinter module"
        return 0
    fi

    # Ensure state directory exists
    mkdir -p "/var/lib/rpi-config/state"

    # Define image defaults (can be overridden in config)
    local def_octoprint="${CONFIG[3dprinter_octoprint_image]:-octoprint/octoprint:latest}"
    local def_octoklipper="${CONFIG[3dprinter_octoklipper_image]:-octoklipper/octoklipper:latest}"
    local def_orcaslicer="${CONFIG[3dprinter_orcaslicer_image]:-orcaslicer/orcaslicer:latest}"
    local def_manyfold="${CONFIG[3dprinter_manyfold_image]:-manyfold/manyfold:latest}"
    local def_kiauh_repo="${CONFIG[3dprinter_kiauh_repo]:-https://github.com/dw-0/kiauh}"
    local def_kiauh_path="${CONFIG[3dprinter_kiauh_path]:-/opt/kiauh}"

    IFS=',' read -ra svcs <<<"$services"

    # Determine if any container-backed services were requested
    local container_requested="false"
    for s in "${svcs[@]}"; do
        s="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' <<<"$s")"
        if 3dprinter::is_container_service "$s"; then
            container_requested="true"
            break
        fi
    done

    local runtime=""
    if [[ "$container_requested" == "true" ]]; then
        runtime="$(3dprinter::detect_runtime || true)"
        if [[ -z "$runtime" ]]; then
            log_warning "No container runtime available; container-backed services will be skipped"
        else
            log_info "Using container runtime: $runtime"
        fi
    fi

    for s in "${svcs[@]}"; do
        s="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' <<<"$s")"
        
        # Check if this service was already configured
        local state_file="/var/lib/rpi-config/state/3dprinter_${s}_configured"
        if [[ -f "$state_file" ]] && [[ "${CONFIG[3dprinter_force_reconfigure]:-false}" != "true" ]]; then
            log_info "Service '$s' already configured - skipping (set 3dprinter_force_reconfigure=true to override)"
            continue
        fi
        
        case "$s" in
            octoprint)
                [[ -z "$runtime" ]] && { log_warning "Skipping 'octoprint' - container runtime not available"; continue; }
                3dprinter::pull_image "$runtime" "$def_octoprint" "octoprint" || { log_error "Failed to pull octoprint"; continue; }
                3dprinter::create_systemd_service "$runtime" "octoprint" "$def_octoprint" || { log_error "Failed to create service for octoprint"; continue; }
                touch "$state_file"
                ;;
            octoklipper)
                [[ -z "$runtime" ]] && { log_warning "Skipping 'octoklipper' - container runtime not available"; continue; }
                3dprinter::pull_image "$runtime" "$def_octoklipper" "octoklipper" || { log_error "Failed to pull octoklipper"; continue; }
                3dprinter::create_systemd_service "$runtime" "octoklipper" "$def_octoklipper" || { log_error "Failed to create service for octoklipper"; continue; }
                touch "$state_file"
                ;;
            orcaslicer)
                [[ -z "$runtime" ]] && { log_warning "Skipping 'orcaslicer' - container runtime not available"; continue; }
                3dprinter::pull_image "$runtime" "$def_orcaslicer" "orcaslicer" || { log_error "Failed to pull orcaslicer"; continue; }
                3dprinter::create_systemd_service "$runtime" "orcaslicer" "$def_orcaslicer" || { log_error "Failed to create service for orcaslicer"; continue; }
                touch "$state_file"
                ;;
            manyfold)
                [[ -z "$runtime" ]] && { log_warning "Skipping 'manyfold' - container runtime not available"; continue; }
                3dprinter::pull_image "$runtime" "$def_manyfold" "manyfold" || { log_error "Failed to pull manyfold"; continue; }
                3dprinter::create_systemd_service "$runtime" "manyfold" "$def_manyfold" || { log_error "Failed to create service for manyfold"; continue; }
                touch "$state_file"
                ;;
            fluidd)
                # Non-container: only clone/update KIAUH
                3dprinter::setup_kiauh "$def_kiauh_repo" "$def_kiauh_path" || { log_error "Failed to setup KIAUH"; continue; }
                touch "$state_file"
                ;;
            *)
                log_warning "Unknown 3dprinter service: $s"
                ;;
        esac
    done
}

3dprinter::detect_runtime() {
    local cfg_runtime="${CONFIG[container_runtime]:-podman}"
    cfg_runtime="$(tr '[:upper:]' '[:lower:]' <<<"$cfg_runtime")"

    if [[ "$cfg_runtime" == "none" ]]; then
        return 1
    fi

    if command -v podman >/dev/null 2>&1 && [[ "$cfg_runtime" != "docker" ]]; then
        echo "podman"
    elif command -v docker >/dev/null 2>&1 && [[ "$cfg_runtime" != "podman" ]]; then
        echo "docker"
    elif [[ "$cfg_runtime" == "both" ]]; then
        if command -v podman >/dev/null 2>&1; then
            echo "podman"
        elif command -v docker >/dev/null 2>&1; then
            echo "docker"
        fi
    elif command -v podman >/dev/null 2>&1; then
        echo "podman"
    elif command -v docker >/dev/null 2>&1; then
        echo "docker"
    fi
}

## @fn 3dprinter::pull_image
## @brief Pull container image for a service
## @description Downloads the specified container image using the configured runtime
## @param runtime Container runtime (podman or docker)
## @param image Full image name (e.g., octoprint/octoprint:latest)
## @param name Service name for logging
## @return 0 on success (even if pull fails - logged as warning)
## @example 3dprinter::pull_image "podman" "octoprint/octoprint:latest" "octoprint"
3dprinter::pull_image() {
    local runtime="$1"
    local image="$2"
    local name="$3"

    log_info "Pulling $name image: $image"
    if [[ "$runtime" == "podman" ]]; then
        if podman pull "$image"; then
            log_success "Pulled $image via podman"
        else
            log_warning "Failed to pull $image"
        fi
    else
        if docker pull "$image"; then
            log_success "Pulled $image via docker"
        else
            log_warning "Failed to pull $image"
        fi
    fi
}

## @fn 3dprinter::create_systemd_service
## @brief Create and enable systemd service for container
## @description Generates environment file and systemd unit for the service
## @param runtime Container runtime (podman or docker)
## @param name Service name (octoprint, orcaslicer, etc.)
## @param image Container image to run
## @return 0 on success, 1 on failure
## @note Creates files in /etc/default/ and /etc/systemd/system/
3dprinter::create_systemd_service() {
    local runtime="$1"
    local name="$2"
    local image="$3"

    local env_file="/etc/default/3dprinter-${name}"
    local unit_file="/etc/systemd/system/3dprinter-${name}.service"

    case "$name" in
        octoprint)
            cat > "$env_file" <<'EOF'
IMAGE="octoprint/octoprint:latest"
RUN_ARGS="-p 5000:80 -v /srv/octoprint:/config"
EOF
            ;;
        octoklipper)
            cat > "$env_file" <<'EOF'
IMAGE="octoklipper/octoklipper:latest"
RUN_ARGS="-p 7125:7125 -v /srv/octoklipper:/config --device=/dev/ttyUSB0"
EOF
            ;;
        orcaslicer)
            cat > "$env_file" <<'EOF'
IMAGE="orcaslicer/orcaslicer:latest"
RUN_ARGS="-p 8080:80 -v /srv/orcaslicer:/data"
EOF
            ;;
        manyfold)
            cat > "$env_file" <<'EOF'
IMAGE="manyfold/manyfold:latest"
RUN_ARGS="-p 8000:8000 -v /srv/manyfold:/data"
EOF
            ;;
        fluidd)
            # Non-container service; no unit or image for fluidd
            log_info "Fluidd is managed via KIAUH; no systemd unit or container will be created"
            return 0
            ;;
    esac
    
    # Ensure env_file was created
    if [[ ! -f "$env_file" ]]; then
        log_error "Failed to create environment file: $env_file"
        return 1
    fi
    
    chmod 644 "$env_file"

    systemctl disable --now "3dprinter-${name}.service" >/dev/null 2>&1 || true
    rm -f "$unit_file" >/dev/null 2>&1 || true

    if [[ "$runtime" == "podman" ]]; then
        # shellcheck source=/dev/null
        source "$env_file"

        podman rm -f "$name" >/dev/null 2>&1 || true

        if podman create --name "$name" ${RUN_ARGS} "${image}"; then
            log_info "Podman container '$name' created"

            if podman generate systemd --new --name "$name" > "$unit_file" 2>/dev/null; then
                chmod 644 "$unit_file"
                systemctl daemon-reload
                if systemctl enable --now "3dprinter-${name}.service"; then
                    log_success "Systemd unit created and started: 3dprinter-${name}.service"
                else
                    log_warning "Failed to start unit"
                fi
            else
                log_warning "podman generate systemd failed; falling back to wrapper unit"
                3dprinter::create_wrapper_unit "$name" "$env_file"
            fi
        else
            log_warning "Failed to create podman container '$name'"
        fi
    else
        3dprinter::create_wrapper_unit "$name" "$env_file"
    fi
}

## @fn 3dprinter::create_wrapper_unit
## @brief Create Docker wrapper systemd unit
## @description Fallback method for Docker (or failed podman generate)
## @param name Service name
## @param env_file Path to environment file
## @return 0 on success, 1 on failure
3dprinter::create_wrapper_unit() {
    local name="$1"
    local env_file="$2"
    local unit_file="/etc/systemd/system/3dprinter-${name}.service"

    docker rm -f "$name" >/dev/null 2>&1 || true

    cat > "$unit_file" <<EOF
[Unit]
Description=3DPrinter service: ${name}
After=network.target

[Service]
Restart=always
EnvironmentFile=-${env_file}
ExecStart=/bin/sh -c 'exec /usr/bin/docker run --name ${name} \${RUN_ARGS} \${IMAGE}'
ExecStop=/bin/sh -c '/usr/bin/docker stop -t 10 ${name} || true'
ExecStopPost=/bin/sh -c '/usr/bin/docker rm -f ${name} || true'
Type=simple

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 "$unit_file"
    systemctl daemon-reload
    if systemctl enable --now "3dprinter-${name}.service"; then
        log_success "Wrapper systemd unit created and started: 3dprinter-${name}.service"
    else
        log_warning "Failed to start unit"
    fi
}

## @fn 3dprinter::is_container_service
## @brief Check if a service is container-backed
## @description Returns 0 if service is managed via containers, 1 otherwise.
## @param name Service name to check
## @return 0 if container-backed, 1 if not
## @example if 3dprinter::is_container_service "octoprint"; then echo "Uses container"; fi
3dprinter::is_container_service() {
    local name="${1:-}"
    case "$name" in
        octoprint|octoklipper|orcaslicer|manyfold) return 0 ;;
        *) return 1 ;;
    esac
}

## @fn 3dprinter::ensure_git
## @brief Ensure git is installed (idempotent)
## @description Installs git and ca-certificates if not present
## @return 0 if git available, 1 on installation failure
3dprinter::ensure_git() {
    if command -v git >/dev/null 2>&1; then
        return 0
    fi
    log_info "git not found; installing"
    apt-get update -qq || { log_error "apt-get update failed"; return 1; }
    apt-get install -y git ca-certificates >/dev/null || { log_error "Failed to install git"; return 1; }
    log_success "git installed"
}

## @fn 3dprinter::setup_kiauh
## @brief Clone or update KIAUH (for Fluidd)
## @description Clones KIAUH repository if missing, updates if present
## @param repo URL of the KIAUH repository
## @param dest Destination directory (default /opt/kiauh)
## @return 0 on success, 1 on failure
## @note Creates state file to track completion
## @warning Fails if destination exists but is not a git repository
3dprinter::setup_kiauh() {
    local repo="$1"
    local dest="$2"

    log_step "Preparing KIAUH for Fluidd at: ${dest}"
    3dprinter::ensure_git || return 1

    # Idempotency state tracking
    local state_dir="/var/lib/rpi-config/state"
    mkdir -p "$state_dir"

    if [[ -e "$dest" && ! -d "$dest/.git" ]]; then
        log_error "Destination exists but is not a git repo: $dest"
        return 1
    fi

    if [[ ! -d "$dest" ]]; then
        log_info "Cloning KIAUH repository: $repo -> $dest"
        if ! mkdir -p "$(dirname "$dest")"; then
            log_error "Failed to create parent directory for $dest"
            return 1
        fi
        
        if git clone --depth=1 "$repo" "$dest" >/dev/null 2>&1; then
            chmod 755 "$dest" || true
            log_success "KIAUH cloned to $dest"
        else
            log_error "Failed to clone KIAUH"
            return 1
        fi
    else
        # Already cloned: update to latest without breaking idempotency
        log_info "KIAUH already present; updating"
        if git -C "$dest" fetch --quiet --all --prune && git -C "$dest" pull --ff-only --quiet 2>/dev/null; then
            log_success "KIAUH updated"
        else
            log_warning "Failed to update KIAUH; leaving existing clone intact"
        fi
    fi
}