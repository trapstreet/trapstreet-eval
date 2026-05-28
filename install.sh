#!/usr/bin/env bash
# Installer for the trapstreet-eval Claude Code skill.
#
# Two modes auto-detected:
#   • Local clone — run `bash install.sh` from a checkout, copies the
#     sibling SKILL.md.
#   • Remote — `bash <(curl -fsSL .../install.sh)`, downloads SKILL.md
#     from raw.githubusercontent.com.
#
# Set TRAPSTREET_FORCE_REMOTE=1 to use remote mode even from a clone.

set -euo pipefail

DEST="${TRAPSTREET_DEST:-$HOME/.claude/skills/trapstreet-eval}"
REMOTE_BASE="https://raw.githubusercontent.com/trapstreet/trapstreet-eval/main"

# Detect local-clone mode by checking whether BASH_SOURCE[0] is a real
# file on disk. When piped via `bash <(curl)` it's a /dev/fd/* pipe
# and `-f` fails.
LOCAL_SKILL=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  [[ -f "$SCRIPT_DIR/SKILL.md" ]] && LOCAL_SKILL="$SCRIPT_DIR/SKILL.md"
fi

mkdir -p "$DEST"

if [[ -n "$LOCAL_SKILL" && "${TRAPSTREET_FORCE_REMOTE:-0}" != "1" ]]; then
  printf '\033[36m→\033[0m installing from local clone: %s\n' "$LOCAL_SKILL"
  install -m 644 "$LOCAL_SKILL" "$DEST/SKILL.md"
else
  printf '\033[36m→\033[0m downloading SKILL.md from %s\n' "$REMOTE_BASE"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --proto '=https' --tlsv1.2 "$REMOTE_BASE/SKILL.md" -o "$DEST/SKILL.md"
  elif command -v wget >/dev/null 2>&1; then
    wget -q "$REMOTE_BASE/SKILL.md" -O "$DEST/SKILL.md"
  else
    printf '\033[31merror:\033[0m need curl or wget on PATH\n' >&2
    exit 1
  fi
  chmod 644 "$DEST/SKILL.md"
fi

printf '\033[32m✓\033[0m installed to %s\n' "$DEST"
printf '\033[32m✓\033[0m run /trapstreet-eval in any Claude Code session\n'
printf '   pass an optional task id, e.g.: /trapstreet-eval financebench\n'
