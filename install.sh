#!/usr/bin/env bash
# Installer for the trapstreet-eval Claude Code skill.
#
# What this script does:
#   • Copies SKILL.md, SECURITY.md, README.md AND the entire `tasks/`
#     tree (task data + judge.py for every bundled trapstreet task)
#     into ~/.claude/skills/trapstreet-eval/.
#
# Two modes auto-detected:
#   • Local clone — run `bash install.sh` from a checkout, copies from
#     sibling files.
#   • Remote — `bash <(curl -fsSL .../install.sh)`, falls back to a
#     shallow `git clone` of trapstreet/trapstreet-eval and runs the
#     local-mode copy from that checkout. (We git-clone instead of
#     curl-each-file because the bundled tasks/ tree has dozens of small
#     files that would be tedious to enumerate over HTTP.)
#
# Set TRAPSTREET_FORCE_REMOTE=1 to use remote mode even from a clone.
# Override TRAPSTREET_REPO_URL / TRAPSTREET_REF to install from a fork
# or branch.
#
# What this script does NOT do:
#   • No sudo. No system-wide changes. No package installs.
#   • Does not modify shell rc files.
#   • Does not write outside $DEST.
#   • Does not phone home. (`tp auth login` does, but that's a separate
#     command run by the user, not by this installer.)

set -euo pipefail

DEST="${TRAPSTREET_DEST:-$HOME/.claude/skills/trapstreet-eval}"
REPO_URL="${TRAPSTREET_REPO_URL:-https://github.com/trapstreet/trapstreet-eval.git}"
REF="${TRAPSTREET_REF:-main}"

err()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[36m→\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }

# Files to copy from the source checkout into $DEST.
# Anything not in this list is ignored (e.g. .git, install.sh itself).
TOP_LEVEL=(SKILL.md SECURITY.md README.md)
DIRS=(tasks)

copy_from() {
  local src="$1"
  mkdir -p "$DEST"
  for f in "${TOP_LEVEL[@]}"; do
    [[ -f "$src/$f" ]] || err "missing in source: $f"
    install -m 644 "$src/$f" "$DEST/$f"
  done
  for d in "${DIRS[@]}"; do
    [[ -d "$src/$d" ]] || err "missing in source: $d/"
    rm -rf "$DEST/$d"
    cp -R "$src/$d" "$DEST/$d"
    # Make every judge.py executable (skill calls them via `python3 ...`
    # so this is belt-and-suspenders, but cheap).
    find "$DEST/$d" -name "judge.py" -exec chmod +x {} \;
  done
}

# Detect local-clone mode by checking whether BASH_SOURCE[0] is a real
# file on disk. When piped via `bash <(curl)` it's a /dev/fd/* pipe and
# `-f` fails.
LOCAL_SRC=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  [[ -f "$SCRIPT_DIR/SKILL.md" && -d "$SCRIPT_DIR/tasks" ]] && LOCAL_SRC="$SCRIPT_DIR"
fi

if [[ -n "$LOCAL_SRC" && "${TRAPSTREET_FORCE_REMOTE:-0}" != "1" ]]; then
  info "installing from local clone: $LOCAL_SRC"
  copy_from "$LOCAL_SRC"
else
  command -v git >/dev/null 2>&1 || err "need git on PATH for remote install"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  info "cloning $REPO_URL @ $REF"
  git clone --depth 1 --branch "$REF" "$REPO_URL" "$TMP/checkout" >/dev/null
  copy_from "$TMP/checkout"
fi

ok "installed trapstreet-eval to $DEST"
ok "bundled tasks: $(ls "$DEST/tasks" | tr '\n' ' ')"
ok "run /trapstreet-eval in any Claude Code session"
echo "   pass an optional task id, e.g.: /trapstreet-eval financebench"
echo "   uninstall: rm -rf $DEST"
