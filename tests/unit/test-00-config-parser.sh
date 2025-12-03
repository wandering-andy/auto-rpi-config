#!/bin/bash
set -euo pipefail

# Create a temporary config
tmp_cfg="$(mktemp)"
cat >"$tmp_cfg" <<'YAML'
system:
  hostname: "pi-test"
ssh:
  port: 2222
  public_key: "ssh-ed25519 AAAA... test@host"
docker:
  enabled: true
YAML

# Point parser to temp config
export CONFIG_FILE="$tmp_cfg"

# shellcheck source=../../scripts/lib/config-parser.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib/config-parser.sh"

# Basic value checks
[[ "$(get_config ".system.hostname")" == "pi-test" ]]
[[ "$(get_config ".ssh.port")" == "2222" ]]
[[ "$(get_config_bool ".docker.enabled")" == "true" ]]

# Require keys should pass
require_keys ".system.hostname" ".ssh.port" ".ssh.public_key"

# Missing key should fail
if require_keys ".missing.key"; then
  echo "ERROR: require_keys should have failed for missing key" >&2
  exit 1
fi

echo "✓ config-parser unit tests passed"
rm -f "$tmp_cfg"
