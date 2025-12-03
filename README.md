# auto-rpi-config

Automated Raspberry Pi configuration system for homelab deployments

## Overview

Idempotent, modular configuration system for Raspberry Pi OS Lite (Debian Trixie).
Designed for headless deployment with fail-safe defaults and comprehensive error handling.

## Quick Start

```bash
# 1. Clone and configure
git clone <repo-url>
cd auto-rpi-config
cp config.yml.example config.yml
nano config.yml  # Edit for your Pi

# 2. Validate configuration
./tests/validate-config.sh config.yml

# 3. Run configuration (as root)
sudo ./auto-rpi-config.sh config.yml
# Or use a custom-named config file:
sudo ./auto-rpi-config.sh my-pi-config.yml

# 4. Check system health
./health-check.sh
```

## Features

- Idempotent - Safe to re-run multiple times
- Modular - Enable only what you need via YAML
- Container support - Podman, Docker, K3s
- 3D Printing - OctoPrint, OrcaSlicer, Manyfold (containers); Klipper/Fluidd (via KIAUH)
- Security hardening - SSH key-only, auto-updates
- NVMe optimizations - For Raspberry Pi 5
- Health monitoring - System status checks

## Available Modules

- **core** - Core functions for logging, validation, and YAML parsing
- **3dprinter** - Container-based 3D printing services and KIAUH installer
- **containers** - Container runtime installation and configuration
- **desktop** - Desktop environment setup
- **development** - Development tools and configurations
- **monitoring** - System monitoring and health checks
- **network** - Network configuration and VPN setup
- **nvme** - NVMe drive optimizations
- **security** - Security hardening and SSH configuration
- **system** - Base system configuration

See [DEVELOPERS.md](DEVELOPERS.md) for detailed module documentation.

## Configuration Examples

### Minimal Headless Server

```yaml
hostname: pi-server
username: admin
timezone: America/New_York
locale: en_US.UTF-8
container_runtime: podman
```

### 3D Printer Host

```yaml
hostname: octoprint-pi
container_runtime: docker
3dprinter_services: "octoprint,orcaslicer"
```

### Klipper with Fluidd

```yaml
hostname: klipper-pi
container_runtime: none
3dprinter_services: "fluidd"
```

See `config.yml.example` for all available options.

## Development

```bash
make lint        # ShellCheck linting
make test        # Validate config.yml.example
make docs        # Regenerate documentation
make permissions # Fix file permissions
```

See [DEVELOPERS.md](DEVELOPERS.md) for contribution guidelines.

## License

GNU General Public License v3.0

---

*Last updated: 2024-01-15 18:30:00 UTC*
