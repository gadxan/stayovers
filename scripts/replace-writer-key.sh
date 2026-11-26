#!/bin/bash
# Replaces the backup writer key with one that can only ADD files to the backup bucket,
# saves it straight into GitHub, tests it, then deletes the old over-powered key.
#
# You copy your Backblaze MASTER keyID and applicationKey when asked (Backblaze →
# Application Keys → Generate New Master Application Key). They are read from the
# clipboard, used for this run only, never printed and never saved to disk.
set -euo pipefail

B2=${B2:-$HOME/.local/bin/b2}
GH=${GH:-/Users/macbookpro/bin/gh}
REPO=gadxan/stayovers
BUCKET=stayover-backups-ss9ekcdf
NEW_NAME=stayover-backup-adder
OLD_NAME=stayover-backup-writer
# Only what an upload needs. No deleteFiles, no bucket or retention changes, no reading.
CAPS=listBuckets,listAllBucketNames,readBucketEncryption,writeFiles

WORK=$(mktemp -d)
cleanup() { rm -rf "$WORK"; unset B2_APPLICATION_KEY_ID B2_APPLICATION_KEY; pbcopy </dev/null; }
trap cleanup EXIT

echo "== Step 1 of 4: master key (used for this run only) =="
echo "Copy the master keyID and the master applicationKey, one at a time, in any order."
echo "Press Enter after each copy."
MID=""; MKEY=""
while [[ -z "$MID" || -z "$MKEY" ]]; do
  if [[ -z "$MID" && -z "$MKEY" ]]; then need="either one"
  elif [[ -z "$MID" ]]; then need="the keyID"
  else need="the applicationKey"; fi
  read -r -p "Copy $need, then press Enter: " _
  v=$(pbpaste | tr -d '[:space:]')
  if [[ "$v" =~ ^[0-9a-f]{12}$|^[0-9a-f]{25}$ ]]; then
    MID=$v; echo "  ✓ keyID read (${#v} characters)"
  elif [[ "$v" =~ ^[A-Za-z0-9+/]{31}$|^[A-Za-z0-9+/]{42}$ ]]; then
    MKEY=$v; echo "  ✓ applicationKey read (${#v} characters)"
  else
    echo "  ✗ The clipboard holds neither (length ${#v}). Copy again."
  fi
done
unset v

export B2_ACCOUNT_INFO="$WORK/master.sqlite"
B2_APPLICATION_KEY_ID=$MID B2_APPLICATION_KEY=$MKEY "$B2" account authorize >/dev/null
unset MKEY
echo "  ✓ signed in to Backblaze"

echo "== Step 2 of 4: create the add-only key and save it to GitHub =="
read -r NEW_ID NEW_KEY < <("$B2" key create --bucket "$BUCKET" "$NEW_NAME" "$CAPS")
[[ "$NEW_ID" =~ ^[0-9a-f]{25}$ && ${#NEW_KEY} -eq 31 ]] || { echo "✗ Unexpected reply from Backblaze; nothing changed in GitHub."; exit 1; }
printf '%s' "$NEW_ID"  | "$GH" secret set B2_KEY_ID -R "$REPO"
printf '%s' "$NEW_KEY" | "$GH" secret set B2_KEY    -R "$REPO"
echo "  ✓ new key '$NEW_NAME' saved as B2_KEY_ID / B2_KEY"

echo "== Step 3 of 4: test the new key =="
(
  export B2_ACCOUNT_INFO="$WORK/new.sqlite"
  B2_APPLICATION_KEY_ID=$NEW_ID B2_APPLICATION_KEY=$NEW_KEY "$B2" account authorize >/dev/null
  echo "  capabilities: $("$B2" account get | python3 -c 'import json,sys; print(",".join(json.load(sys.stdin)["allowed"]["capabilities"]))')"
  STAMP=$(date -u +%Y%m%dT%H%M%SZ)
  echo "key check $STAMP" > "$WORK/keycheck.txt"
  "$B2" file upload "$BUCKET" "$WORK/keycheck.txt" "daily/keycheck-$STAMP.txt" >/dev/null
  echo "  ✓ test upload worked (daily/keycheck-$STAMP.txt, cleared automatically later)"
)
unset NEW_KEY

echo "== Step 4 of 4: delete the old over-powered key =="
OLD_IDS=$("$B2" key list | awk -v n="$OLD_NAME" '$2==n {print $1}')
if [[ -z "$OLD_IDS" ]]; then
  echo "  (no key named $OLD_NAME found; nothing to delete)"
else
  echo "  Found $(echo "$OLD_IDS" | wc -l | tr -d ' ') key(s) named $OLD_NAME. Deleting a key only stops it working; no files are touched."
  read -r -p "  Type DELETE to delete it, or just press Enter to keep it: " ans
  if [[ "$ans" == "DELETE" ]]; then
    for id in $OLD_IDS; do "$B2" key delete "$id" >/dev/null; done
    echo "  ✓ old key deleted"
  else
    echo "  kept the old key"
  fi
fi

echo
echo "Remaining keys:"; "$B2" key list | awk '{print "  - " $2}'
echo "DONE. Your clipboard has been cleared."
