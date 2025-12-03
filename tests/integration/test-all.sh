#!/bin/bash
set -euo pipefail

echo "system:
  hostname: integpi
ssh:
  port: 2222
  public_key: ssh-ed25519 AAAAintegrationkey integration@test" > config.yml

# Mock systemctl in container context (if not privileged)
systemctl() {
    case "$1" in
        restart|enable|start) return 0 ;;
        is-active) return 0 ;;
    esac
}

./config-runner.sh || { echo "ERROR: integration run failed" >&2; exit 1; }
./config-runner.sh || { echo "ERROR: idempotent second run failed" >&2; exit 1; }

echo "✓ integration test passed."
