#!/usr/bin/env bash
# _safer-zapbot-env.sh — source this to resolve zapbot config.
#
# Self-source zapbot config: explicit env var > .env > config.json (zapbot#302 forward-compat)
# Uses subshell isolation to prevent .env from spoofing bootstrap locals.
# Sets ZAPBOT_API_KEY in the calling environment.
# Exit: always 0.

_sbd_explicit_key="${ZAPBOT_API_KEY:-}"
_sbd_was_set="${ZAPBOT_API_KEY+set}"
ZAPBOT_API_KEY=$(_sbd_explicit_key="$_sbd_explicit_key" _sbd_was_set="$_sbd_was_set" bash << 'ZAPBOT_BOOTSTRAP'
  [ -f "$HOME/.zapbot/.env" ] && { set -a; . "$HOME/.zapbot/.env"; set +a; }
  if [ "$_sbd_was_set" = "set" ]; then
    echo "$_sbd_explicit_key"
  elif [ -z "${ZAPBOT_API_KEY:-}" ] && [ -f "$HOME/.zapbot/config.json" ]; then
    _api_key=$(jq -r '.apiKey // empty' "$HOME/.zapbot/config.json" 2>/dev/null)
    [ -n "$_api_key" ] && echo "$_api_key" || echo ""
  else
    echo "${ZAPBOT_API_KEY:-}"
  fi
ZAPBOT_BOOTSTRAP
)
export ZAPBOT_API_KEY
unset _sbd_explicit_key _sbd_was_set
