#!/bin/bash

## @module Desktop
## @brief Desktop environment and application configuration

## @fn desktop::configure
## @brief Configure desktop environment and applications
desktop::configure() {
    log_step "Configuring desktop environment"

    desktop::install_desktop_packages
    desktop::install_lite_xl
    desktop::configure_autologin
    desktop::configure_compositor
}

## @fn desktop::install_desktop_packages
## @brief Install desktop environment packages
desktop::install_desktop_packages() {
    log_info "Installing minimal desktop environment"

    apt-get install -y --no-install-recommends \
        lxqt-core \
        labwc \
        wayland-protocols \
        xwayland \
        firefox-esr

    log_success "Minimal desktop packages installed"
}

## @fn desktop::install_lite_xl
## @brief Install Lite XL text editor from latest binary
desktop::install_lite_xl() {
    log_info "Installing Lite XL text editor"

    local latest_info download_url package_name
    latest_info=$(curl -s https://api.github.com/repos/lite-xl/lite-xl/releases/latest)
    download_url=$(echo "$latest_info" | grep "browser_download_url.*aarch64.*tar.gz" | head -1 | cut -d '"' -f 4)

    if [[ -z "$download_url" ]]; then
        log_error "Could not find Lite XL download URL"
        return 1
    fi

    log_info "Downloading latest Lite XL: $(basename "$download_url")"
    package_name=$(basename "$download_url")
    wget "$download_url" -O "$package_name"

    log_info "Extracting and installing Lite XL"
    tar -xzf "$package_name"

    local extract_dir
    extract_dir=$(tar -tzf "$package_name" | head -1 | cut -f1 -d"/")

    cp "$extract_dir/lite-xl" /usr/local/bin/
    mkdir -p /usr/local/share/lite-xl
    cp -r "$extract_dir"/data/* /usr/local/share/lite-xl/ 2>/dev/null || true

    cat > /usr/share/applications/lite-xl.desktop <<EOF
[Desktop Entry]
Name=Lite XL
Comment=A lightweight text editor written in Lua
Exec=lite-xl
Icon=text-editor
Terminal=false
Type=Application
Categories=Development;TextEditor;
Keywords=text;editor;
EOF

    rm -rf "$package_name" "$extract_dir"

    log_success "Lite XL installed successfully"
}

## @fn desktop::configure_autologin
## @brief Configure automatic login to desktop
desktop::configure_autologin() {
    if [[ "${CONFIG[enable_autologin]}" != "true" ]]; then
        log_info "Autologin disabled by configuration"
        return 0
    fi

    log_info "Configuring automatic login"

    cat > /usr/share/wayland-sessions/labwc.desktop <<EOF
[Desktop Entry]
Name=LabWC
Comment=Lightweight Wayland compositor
Exec=labwc
Type=Application
EOF

    mkdir -p /etc/sddm.conf.d

    cat > /etc/sddm.conf.d/autologin.conf <<EOF
[Autologin]
User=${CONFIG[username]}
Session=labwc.desktop
EOF

    log_info "Autologin configured for LabWC"
    core::mark_reboot_required
}

## @fn desktop::configure_compositor
## @brief Configure Wayland compositor
desktop::configure_compositor() {
    log_info "Configuring LabWC compositor (tiling-ready)"

    mkdir -p /home/"${CONFIG[username]}"/.config/labwc

    cat > /home/"${CONFIG[username]}"/.config/labwc/rc.xml <<'EOF'
<?xml version="1.0"?>
<labwc_config>
    <core>
        <gap>5</gap>
    </core>
    <theme>
        <name>default</name>
        <cornerRadius>4</cornerRadius>
    </theme>
    <keyboard>
        <keybind key="A-F4">
            <action name="Close"/>
        </keybind>
        <keybind key="A-Tab">
            <action name="NextWindow"/>
        </keybind>
        <keybind key="W-Return">
            <action name="Execute">
                <command>alacritty</command>
            </action>
        </keybind>
        <keybind key="W-e">
            <action name="Execute">
                <command>lite-xl</command>
            </action>
        </keybind>
        <keybind key="W-f">
            <action name="Execute">
                <command>firefox</command>
            </action>
        </keybind>
    </keyboard>
</labwc_config>
EOF

    mkdir -p /home/"${CONFIG[username]}"/.local/bin
    cat > /home/"${CONFIG[username]}"/.local/bin/start-apps <<'EOF'
#!/bin/bash
# Simple app starter - compatible with any compositor
lite-xl &
firefox &
EOF

    chmod +x /home/"${CONFIG[username]}"/.local/bin/start-apps
    chown -R "${CONFIG[username]}:${CONFIG[username]}" /home/"${CONFIG[username]}"/.config
    chown -R "${CONFIG[username]}:${CONFIG[username]}" /home/"${CONFIG[username]}"/.local

    log_success "LabWC configured with tiling-friendly settings"
}