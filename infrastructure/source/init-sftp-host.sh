#!/usr/bin/env bash
# Prepare host bind mounts only; safe to rerun without replacing SSH host identity.
set -euo pipefail

BASE=/opt/fabric-sftp
sudo mkdir -p "$BASE/data/outbound/inventory/movements" "$BASE/hostkeys"
sudo chown -R 1001:1001 "$BASE/data/outbound"

if ! sudo test -f "$BASE/hostkeys/ssh_host_ed25519_key"; then
  sudo ssh-keygen -q -t ed25519 -N '' -f "$BASE/hostkeys/ssh_host_ed25519_key"
fi
sudo chmod 600 "$BASE/hostkeys/ssh_host_ed25519_key"
sudo chmod 644 "$BASE/hostkeys/ssh_host_ed25519_key.pub"

echo "SFTP host folders and persistent host key ready."
echo "Host-key fingerprint:"
sudo ssh-keygen -E md5 -lf "$BASE/hostkeys/ssh_host_ed25519_key.pub"
echo "Provide SFTP_PASSWORD in the Compose .env; do not commit credentials."
