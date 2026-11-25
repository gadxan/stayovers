#!/usr/bin/env bash
# Restores an unpacked Stayover backup folder into a Supabase database and checks it.
# Used by scripts/restore.sh (by hand) and by the nightly test restore and the restore drill.
#
#   TARGET_DB_URL   connection string of the database to restore INTO (required)
#   TARGET_URL      project URL, e.g. https://xxxx.supabase.co   (optional: restore ID files)
#   TARGET_KEY      that project's secret / service_role key      (optional: restore ID files)
#
# Usage: restore-core.sh <unpacked-backup-folder>
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
dir="${1:?backup folder}"
: "${TARGET_DB_URL:?TARGET_DB_URL is not set}"

start=$(date +%s)
echo "1/5 Checking the backup files are intact"
( cd "$dir" && shasum -a 256 -c checksums.sha256 --quiet ) || { echo "Backup files are damaged."; exit 1; }

echo "2/5 Restoring the database"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# Known, documented adjustments for restoring into a new Supabase project:
sed -E 's/^(GRANT "postgres" TO "cli_login_postgres".*)$/-- \1/' "$dir/db/roles.sql" > "$work/roles.sql"
sed -E 's/^(ALTER .* OWNER TO "supabase_admin";)$/-- \1/' "$dir/db/schema.sql" > "$work/schema.sql"
cp "$dir/db/data.sql" "$work/data.sql"
db_start=$(date +%s)
psql --quiet --no-psqlrc --single-transaction --variable ON_ERROR_STOP=1 \
  --file "$work/roles.sql" \
  --file "$work/schema.sql" \
  --command 'SET session_replication_role = replica' \
  --file "$work/data.sql" \
  --dbname "$TARGET_DB_URL" > "$work/restore.log" 2>&1 || { echo "Database restore failed:"; grep -E 'ERROR|FATAL' "$work/restore.log" | head -5; exit 1; }
psql --quiet --no-psqlrc --variable ON_ERROR_STOP=1 --file "$repo/supabase/after-restore.sql" --dbname "$TARGET_DB_URL" > /dev/null
db_secs=$(( $(date +%s) - db_start ))

echo "3/5 Comparing every table with the backup"
psql --no-psqlrc -At --file "$here/counts.sql" --dbname "$TARGET_DB_URL" > "$work/restored-counts.csv"
bash "$here/compare-counts.sh" "$dir/dump-counts.csv" "$work/restored-counts.csv" "restored copy"

files_secs=0
if [ -n "${TARGET_URL:-}" ] && [ -n "${TARGET_KEY:-}" ]; then
  echo "4/5 Restoring guest ID files"
  f_start=$(date +%s)
  node "$here/storage-import.mjs" "$dir"
  files_secs=$(( $(date +%s) - f_start ))
else
  echo "4/5 Skipping ID files (TARGET_URL / TARGET_KEY not given)"
fi

total=$(( $(date +%s) - start ))
echo "5/5 Done. Database ${db_secs}s, files ${files_secs}s, total ${total}s."
echo "RESTORE_SECONDS=$total" > "$dir/../restore-timing.env"
echo "RESTORE_DB_SECONDS=$db_secs" >> "$dir/../restore-timing.env"
echo "RESTORE_FILES_SECONDS=$files_secs" >> "$dir/../restore-timing.env"
