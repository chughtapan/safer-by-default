#!/usr/bin/env bash
# _safer-zapbot-env.sh — source this to resolve zapbot config.
#
# Read ZAPBOT_API_KEY from ~/.zapbot/config.json "apiKey" field.
# Single source of truth: config.json. No explicit env override.

if [ ! -f "$HOME/.zapbot/config.json" ]; then
  echo "safer-zapbot-env: $HOME/.zapbot/config.json not found" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "safer-zapbot-env: jq required to read $HOME/.zapbot/config.json" >&2
  exit 1
fi
_key=$(jq -er '
  if (.apiKey | type) == "string" and (.apiKey | length) > 0
  then .apiKey else empty end
' "$HOME/.zapbot/config.json") || {
  echo "safer-zapbot-env: apiKey missing or not a non-empty string in $HOME/.zapbot/config.json" >&2
  exit 1
}
export ZAPBOT_API_KEY="$_key"
unset _key
