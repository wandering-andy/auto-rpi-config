#!/bin/bash
#
# Unit Test: 04-docker.sh
#
# Description:
#   Tests Docker installation module

set -euo pipefail

# shellcheck source=../../system/04-docker.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../system/04-docker.sh"

# Mock docker + systemctl
command -v docker >/dev/null 2>&1 || {
    docker() { echo "docker mock"; }
}
systemctl() {
    case "$1" in
        enable|start) return 0 ;;
        is-active) return 0 ;;
    esac
}

rm -f /var/lib/rpi-config/state/docker_configured || true
mkdir -p /var/lib/rpi-config/state

configure_docker || { echo "ERROR: First run failed" >&2; exit 1; }
configure_docker || { echo "ERROR: Second run (idempotency) failed" >&2; exit 1; }

echo "✓ docker module unit test passed."
