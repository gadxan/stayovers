#!/usr/bin/env bash
# ONE COMMAND to restore a Stayover backup.
#
#   ./scripts/restore.sh <backup file .tar.gz.cms> <target database URL> [target project URL] [target secret key]
#
# - Asks for the private backup key (paste it, then press Ctrl-D). It is kept in a temporary
#   file readable only by you and deleted when the script ends.
# - Refuses to restore over the live Stayover database unless you type the confirmation.
# - Checks every table and every ID file against the backup and prints how long it took.
#
# Needs: openssl, psql (from Postgres.app or the PostgreSQL installer), node 18+.
set -euo pipefail
LIVE_REF="ajanwxumictvchwrarhh"
here="$(cd "$(dirname "$0")" && pwd)"

file="${1:-}"; db="${2:-}"
if [ -z "$file" ] || [ -z "$db" ]; then
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 2
fi
[ -f "$file" ] || { echo "No such backup file: $file"; exit 2; }
for t in openssl psql node shasum tar; do command -v "$t" >/dev/null || { echo "Missing tool: $t (see docs/BACKUPS.md, 'Restoring')"; exit 2; }; done

if printf '%s' "$db" | grep -q "$LIVE_REF"; then
  echo "WARNING: this target is the LIVE Stayover database. Restoring over it replaces today's data"
  echo "with the backup's data. Make a fresh backup first (GitHub → Actions → Nightly backup → Run)."
  printf 'Type RESTORE OVER LIVE DATA to continue: '
  read -r answer
  [ "$answer" = "RESTORE OVER LIVE DATA" ] || { echo "Stopped. Nothing was changed."; exit 1; }
else
  existing=$(psql --no-psqlrc -At --dbname "$db" -c "select count(*) from information_schema.tables where table_schema='public' and table_name='bookings'" 2>/dev/null || echo 0)
  if [ "$existing" != "0" ]; then
    echo "The target database already has Stayover tables. Restore only into a NEW, empty Supabase project."
    exit 1
  fi
fi

work="$(mktemp -d)"; umask 077
trap 'rm -rf "$work"' EXIT
echo "Paste the private backup key (the block starting -----BEGIN PRIVATE KEY-----), then press Ctrl-D:"
cat > "$work/key.pem"
grep -q "BEGIN PRIVATE KEY" "$work/key.pem" || { echo "That doesn't look like the backup key."; exit 1; }

echo "Decrypting…"
openssl cms -decrypt -binary -inform DER -in "$file" -inkey "$work/key.pem" -out "$work/backup.tar.gz" \
  || { echo "Could not decrypt: wrong key or damaged file."; exit 1; }
rm -f "$work/key.pem"
mkdir "$work/b" && tar -xzf "$work/backup.tar.gz" -C "$work/b"
inner="$(find "$work/b" -mindepth 1 -maxdepth 1 -type d | head -1)"

TARGET_DB_URL="$db" TARGET_URL="${3:-}" TARGET_KEY="${4:-}" bash "$here/backup/restore-core.sh" "$inner"
echo "Restore finished. Backup taken: $(grep -o '"created": *"[^"]*"' "$inner/manifest.json" | cut -d'"' -f4)"
