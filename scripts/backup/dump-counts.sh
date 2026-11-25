#!/usr/bin/env bash
# Counts the rows inside each COPY block of a `supabase db dump --data-only --use-copy` file.
# Prints "schema.table,count" lines, sorted. Usage: dump-counts.sh data.sql
set -euo pipefail
awk '
  /^COPY / { t = $2; gsub(/"/, "", t); n = 0; inblock = 1; next }
  inblock && /^\\\.$/ { print t "," n; inblock = 0; next }
  inblock { n++ }
' "$1" | sort
