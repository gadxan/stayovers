#!/usr/bin/env bash
# Compares two "schema.table,count" files. Every table in the first file must exist in the
# second with exactly the same count. Exit 1 on any difference.
# Usage: compare-counts.sh expected.csv actual.csv [label]
set -euo pipefail
awk -F, -v label="${3:-copy}" '
  NR == FNR { want[$1] = $2; next }
  ($1 in want) {
    if (want[$1] != $2) { printf "MISMATCH %s: backup has %s rows, %s has %s\n", $1, want[$1], label, $2; bad++ }
    else ok++
    delete want[$1]
  }
  END {
    for (k in want) { printf "MISSING %s: in the backup (%s rows) but not in the %s\n", k, want[k], label; bad++ }
    printf "%d table(s) match exactly", ok; if (bad) printf ", %d problem(s)", bad; printf "\n"
    exit (bad > 0)
  }
' "$1" "$2"
