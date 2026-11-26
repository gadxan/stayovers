#!/bin/bash
# Saves whatever B2 reader value is on the clipboard under the right GitHub secret name.
# A B2 keyID is 25 hex characters; an applicationKey starts with "K" and is 31 characters.
# Prints only which secret was set and its length, never the value.
set -euo pipefail
GH=/Users/macbookpro/bin/gh
REPO=gadxan/stayovers
v=$(pbpaste | tr -d '[:space:]')
if [[ "$v" =~ ^[0-9a-f]{25}$ ]]; then
  name=B2_READ_KEY_ID
elif [[ "$v" =~ ^K[A-Za-z0-9+/]{30}$ ]]; then
  name=B2_READ_KEY
else
  echo "✗ The clipboard doesn't look like a B2 keyID or applicationKey (length ${#v}). Copy it again from Backblaze."
  exit 1
fi
printf '%s' "$v" | "$GH" secret set "$name" -R "$REPO"
echo "→ saved as $name (${#v} characters)"
