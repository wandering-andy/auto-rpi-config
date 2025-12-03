#!/bin/bash
#
# Unit Test: 01-hostname.sh
#
# Description:
#   Tests hostname configuration module

set -euo pipefail

# shellcheck source=../../system/01-hostname.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../system/01-hostname.sh"

echo "system:
  hostname: testpi" > config.yml

rm -f /var/lib/rpi-config/state/hostname_configured || true

configure_hostname || { echo "ERROR: First run failed" >&2; exit 1; }
configure_hostname || { echo "ERROR: Second run (idempotency) failed" >&2; exit 1; }

echo "✓ hostname module unit test passed."
