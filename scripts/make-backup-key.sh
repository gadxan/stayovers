#!/usr/bin/env bash
# Makes the backup encryption key pair. Run it ONCE, yourself, in a terminal.
#
#  - The PUBLIC half is saved to backup/backup-public-cert.pem and goes into GitHub. It can only
#    lock backups, never open them.
#  - The PRIVATE half is shown on screen ONCE. Copy it into your password manager (and/or print it
#    and keep the paper somewhere safe). It is then wiped from this computer.
#    Without it, nobody (including you) can open a backup. Keep two copies in different places.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -f backup/backup-public-cert.pem ]; then
  echo "A backup key already exists (backup/backup-public-cert.pem)."
  echo "Making a new one means older backups still need the OLD private key. Stopped."
  exit 1
fi
umask 077
tmp="$(mktemp -d)"
trap 'rm -P "$tmp"/* 2>/dev/null || rm -f "$tmp"/*; rmdir "$tmp"' EXIT
openssl req -x509 -newkey rsa:4096 -nodes -keyout "$tmp/key.pem" -out "$tmp/cert.pem" \
  -days 36500 -subj "/CN=Stayover Mikocheni backups $(date +%Y-%m-%d)" 2>/dev/null
mkdir -p backup && cp "$tmp/cert.pem" backup/backup-public-cert.pem
clear 2>/dev/null || true
echo "=================== PRIVATE BACKUP KEY — COPY ALL OF IT ==================="
cat "$tmp/key.pem"
echo "==========================================================================="
echo "Save everything between the lines (including BEGIN/END) in your password manager,"
echo "as a secure note named: Stayover backup private key"
printf 'Press Enter once it is saved. The key is then erased from this computer… '
read -r _
clear 2>/dev/null || true
echo "Done. Public key saved to backup/backup-public-cert.pem. The private key is no longer on this computer."
echo "Tip: also clear this terminal's scrollback (Cmd-K)."
