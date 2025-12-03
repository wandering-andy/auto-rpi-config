#!/bin/bash
#
# Unit Test: 02-ssh.sh
#
# Description:
#   Tests SSH configuration module

set -euo pipefail

# shellcheck source=../../system/02-ssh.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../system/02-ssh.sh"

echo "system:
  hostname: testpi
ssh:
  port: 2222
  public_key: ssh-ed25519 AAAAexample example@test" > config.yml

rm -f /var/lib/rpi-config/state/ssh_configured || true

# Mock systemctl for unit context
systemctl() {
    case "$1" in
        restart|enable|start) return 0 ;;
        is-active) return 0 ;;
    esac
}

configure_ssh || { echo "ERROR: First run failed" >&2; exit 1; }
configure_ssh || { echo "ERROR: Second run (idempotency) failed" >&2; exit 1; }

echo "✓ ssh module unit test passed."
