#!/usr/bin/env bash
# _safer-zapbot-env.sh — source this to resolve zapbot config.
#
# Self-source zapbot config: explicit env var > .env > config.json (zapbot#302 forward-compat)
# Uses subshell isolation to prevent .env from spoofing bootstrap locals.
# Exports ONLY ZAPBOT_API_KEY to the calling environment (narrow set -a scope per sbd#155).
# Other variables in .env are NOT exported to the caller to prevent accidental leakage.
#
# Dependencies: jq (required only for config.json path; not needed if env var or .env is set).
#
# ERROR POSTURE: loud-and-fail (per sbd#156)
# Malformed inputs cause the helper to exit nonzero with an error message:
# - .env with syntax errors → sourcing fails with parse error
# - config.json with invalid JSON → jq returns error (not suppressed)
# - HOME unset → file checks fail explicitly (not suppressed)
# This matches safer-by-default's fail-fast doctrine (PRINCIPLES #3):
# silent failures hide configuration bugs; explicit errors are preferable to silent degradation.
# Exit: 0 on success, 1 on malformed input or missing jq.

_sbd_explicit_key="${ZAPBOT_API_KEY:-}"
_sbd_was_set="${ZAPBOT_API_KEY+set}"
ZAPBOT_API_KEY=$(_sbd_explicit_key="$_sbd_explicit_key" _sbd_was_set="$_sbd_was_set" bash << 'ZAPBOT_BOOTSTRAP'
  set -ue  # Fail on unset variables (-u) and any command error (-e)

  # Source .env in subshell and extract ONLY ZAPBOT_API_KEY to prevent other variables leaking
  _env_api_key=""
  if [ -f "$HOME/.zapbot/.env" ]; then
    # Loud-and-fail: source .env without suppressing errors
    # Use set -a/+a to export only during source, then capture ZAPBOT_API_KEY
    set -a
    . "$HOME/.zapbot/.env"
    set +a
    _env_api_key="${ZAPBOT_API_KEY:-}"
  fi

  if [ "$_sbd_was_set" = "set" ]; then
    echo "$_sbd_explicit_key"
  elif [ -n "$_env_api_key" ]; then
    echo "$_env_api_key"
  elif [ -f "$HOME/.zapbot/config.json" ]; then
    if command -v jq >/dev/null 2>&1; then
      # Loud-and-fail: jq errors are NOT suppressed (removed 2>/dev/null)
      _api_key=$(jq -r '.apiKey // empty' "$HOME/.zapbot/config.json")
      [ -n "$_api_key" ] && echo "$_api_key" || echo ""
    else
      echo "safer-publish: jq required to read config.json — install jq or unset the config.json fallback" >&2
      exit 1
    fi
  else
    echo ""
  fi
ZAPBOT_BOOTSTRAP
)
_sbd_subshell_exit=$?
export ZAPBOT_API_KEY
[ $_sbd_subshell_exit -eq 0 ] || exit $_sbd_subshell_exit
unset _sbd_explicit_key _sbd_was_set _sbd_subshell_exit
