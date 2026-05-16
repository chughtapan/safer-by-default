#!/usr/bin/env bash
#
# LSP proxy launcher. Claude Code spawns this single command for the safer
# plugin's `.ts`/`.tsx` LSP entry; the script fans the connection out to
# typescript-language-server (primary, for code intelligence) and to the
# safer architecture LSP (sidecar, for architecture diagnostics) via
# lsp-proxy.py. Reason for the indirection: CC's LSP dispatcher cannot
# multiplex multiple servers claiming the same file extensions, so safer
# presents a single server and does the multiplexing internally.
#
# Preconditions installed by /safer:setup:
#   - python3 on PATH
#   - typescript-language-server on PATH
#   - bun on PATH
#   - ~/.local/share/safer-by-default/lsp-proxy.py present (pinned upstream copy)

set -euo pipefail

PROXY="${HOME}/.cache/safer-by-default/lsp-proxy.py"

if [ ! -f "$PROXY" ]; then
  printf 'safer: lsp-proxy.py is missing at %s\n' "$PROXY" >&2
  printf 'safer: run /safer:setup to install it.\n' >&2
  exit 1
fi

# CC sets CLAUDE_PLUGIN_ROOT to the plugin cache root. Resolve it; if the
# variable is empty the script is being invoked outside CC (smoke test, etc.)
# and the architecture LSP path is anchored relative to this script.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT"
else
  PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fi

ARCHITECTURE_ENTRY="${PLUGIN_ROOT}/lsp/architecture/server/index.ts"

if [ ! -f "$ARCHITECTURE_ENTRY" ]; then
  printf 'safer: architecture LSP entry not found at %s\n' "$ARCHITECTURE_ENTRY" >&2
  exit 1
fi

CONFIG="$(mktemp -t safer-lsp-config.XXXXXX.json)"
trap 'rm -f "$CONFIG"' EXIT

cat > "$CONFIG" <<JSON
[
    {
        "cmd": "typescript-language-server",
        "args": ["--stdio"]
    },
    {
        "cmd": "bun",
        "args": ["${ARCHITECTURE_ENTRY}"]
    }
]
JSON

exec python3 "$PROXY" "$CONFIG"
