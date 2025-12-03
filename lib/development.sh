#!/bin/bash

## @module Development
## @brief Development environment configuration

## @fn development::configure
## @brief Configure development environment
development::configure() {
    log_step "Configuring development environment"

    development::install_tools
    development::configure_fish
    development::configure_starship
    development::configure_git
    development::configure_alacritty
}

## @fn development::install_tools
## @brief Install development tools
development::install_tools() {
    log_info "Installing development tools"

    local pkgs=(fish git curl wget vim)
    local want_alacritty="false"

    if [[ "${CONFIG[install_alacritty]:-false}" == "true" ]]; then
        if [[ "${CONFIG[disable_modules]:-}" =~ (^|,)[[:space:]]*desktop([[:space:]]*,|$) ]]; then
            log_info "install_alacritty requested but desktop module is disabled; skipping"
        else
            want_alacritty="true"
            pkgs+=(alacritty)
        fi
    fi

    apt-get update
    apt-get install -y --no-install-recommends "${pkgs[@]}"

    log_success "Development tools installed (alacritty=${want_alacritty})"
}

## @fn development::configure_fish
## @brief Configure Fish shell
development::configure_fish() {
    log_info "Configuring Fish shell"

    if command -v fish >/dev/null 2>&1; then
        chsh -s /usr/bin/fish "${CONFIG[username]}" 2>/dev/null || true
    fi

    local user_home="/home/${CONFIG[username]}"
    mkdir -p "$user_home/.config/fish"

    cat > "$user_home/.config/fish/config.fish" <<'EOF'
# Fish shell configuration
set -gx EDITOR lite-xl
set -gx BROWSER firefox
alias ls='ls --color=auto'
alias ll='ls -la'
alias la='ls -A'
alias grep='grep --color=auto'
alias dps='docker ps'
alias dcu='docker compose up'
alias dcd='docker compose down'
alias pps='podman ps'
if test -d ~/.local/bin
    set -gx PATH ~/.local/bin $PATH
end
EOF

    chown -R "${CONFIG[username]}:${CONFIG[username]}" "$user_home/.config" || true
    log_success "Fish shell configured"
}

## @fn development::configure_starship
## @brief Install and configure Starship prompt
development::configure_starship() {
    log_info "Installing Starship prompt"
    curl -fsSL https://starship.rs/install.sh | sh -s -- -y || log_warning "Starship install failed"

    local user_home="/home/${CONFIG[username]}"
    echo 'starship init fish | source' >> "$user_home/.config/fish/config.fish" 2>/dev/null || true
    echo 'eval "$(starship init bash)"' >> "$user_home/.bashrc" 2>/dev/null || true

    chown -R "${CONFIG[username]}:${CONFIG[username]}" "$user_home" || true
    log_success "Starship prompt installed and configured"
}

## @fn development::configure_git
## @brief Configure Git
development::configure_git() {
    if [[ -n "${CONFIG[git_name]:-}" && -n "${CONFIG[git_email]:-}" ]]; then
        log_info "Configuring Git"
        sudo -u "${CONFIG[username]}" git config --global user.name "${CONFIG[git_name]}" || true
        sudo -u "${CONFIG[username]}" git config --global user.email "${CONFIG[git_email]}" || true
        sudo -u "${CONFIG[username]}" git config --global init.defaultBranch "${CONFIG[git_default_branch]:-main}" || true
        sudo -u "${CONFIG[username]}" git config --global alias.co checkout || true
        sudo -u "${CONFIG[username]}" git config --global alias.br branch || true
        sudo -u "${CONFIG[username]}" git config --global alias.ci commit || true
        sudo -u "${CONFIG[username]}" git config --global alias.st status || true
        log_success "Git configured for ${CONFIG[username]}"
    else
        log_warning "Git name/email not configured, skipping Git setup"
    fi
}

## @fn development::configure_alacritty
## @brief Configure Alacritty terminal
development::configure_alacritty() {
    log_info "Configuring Alacritty terminal"
    local user_home="/home/${CONFIG[username]}"
    mkdir -p "$user_home/.config/alacritty"
    cat > "$user_home/.config/alacritty/alacritty.yml" <<'EOF'
window:
  decorations: none
  opacity: 0.95
  startup_mode: Windowed
  dimensions:
    columns: 120
    lines: 30
font:
  size: 12.0
  normal:
    family: "Monospace"
    style: "Regular"
colors:
  primary:
    background: '#1e1e2e'
    foreground: '#cdd6f4'
cursor:
  style:
    shape: Block
key_bindings:
  - { key: N, mods: Control|Shift, action: SpawnNewInstance }
EOF
    chown -R "${CONFIG[username]}:${CONFIG[username]}" "$user_home/.config" || true
    log_success "Alacritty configured"
}