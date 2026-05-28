#!/usr/bin/env bash
# Local installer for the trapstreet-eval Claude Code skill.
#
# This is the dev / local-test path: copies SKILL.md from this dir into
# ~/.claude/skills/trapstreet-eval/ so Claude Code picks it up as the
# `/trapstreet-eval` slash command.
#
# For the public installer (checksum verification + pinned release tag),
# see trapstreet/trapstreet/skill/install.sh once the skill is published.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${TRAPSTREET_DEST:-$HOME/.claude/skills/trapstreet-eval}"

mkdir -p "$DEST"
install -m 644 "$SCRIPT_DIR/SKILL.md" "$DEST/SKILL.md"

printf '\033[32m✓\033[0m installed to %s\n' "$DEST"
printf '\033[32m✓\033[0m run /trapstreet-eval in any Claude Code session\n'
printf '   pass an optional task id, e.g.: /trapstreet-eval financebench\n'
