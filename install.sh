#!/usr/bin/env bash
# Installer for the "max-messenger" agent skill.
#
#   curl -fsSLO https://raw.githubusercontent.com/max-messenger/max-agents-skill/main/install.sh && bash install.sh
#
# What it does:
#   1. Puts the skill into ~/.agents/skills/max-messenger (read natively by Codex, Cursor,
#      Gemini CLI, OpenCode, GitHub Copilot).
#   2. Symlinks it into harnesses that don't read ~/.agents/skills: Claude Code (~/.claude/skills),
#      Cline (~/.cline/skills) — only if that harness is present on this machine.
#   3. Builds max-messenger-skill.zip for upload into Claude apps (Desktop / Cowork / claude.ai).
#
# Options:
#   --uninstall      remove the skill and the symlinks this script created
#   --local DIR      install from a local copy of the skill instead of downloading
#   --ref REF        branch or tag of the GitHub repo to install (default: main)
#   --no-links       only install into ~/.agents/skills
#   --no-zip         don't build the zip for Claude apps
#   -h, --help       show this help
#
# Env overrides: MAX_SKILL_REPO, MAX_SKILL_REF, MAX_SKILL_TARBALL_URL (mirror), AGENTS_SKILLS_DIR, MAX_SKILL_ZIP_DIR

set -euo pipefail

SKILL_NAME="max-messenger"
SKILL_VERSION="1.0.1"
REPO="${MAX_SKILL_REPO:-max-messenger/max-agents-skill}"
REF="${MAX_SKILL_REF:-main}"
AGENTS_DIR="${AGENTS_SKILLS_DIR:-$HOME/.agents/skills}"
TARGET="$AGENTS_DIR/$SKILL_NAME"
BACKUP_ROOT="$HOME/.cache/agent-skills-backup"

# Harnesses that need a symlink: "label|skills dir|marker that the harness is installed"
LINK_HARNESSES=(
  "Claude Code|$HOME/.claude/skills|$HOME/.claude"
  "Cline|$HOME/.cline/skills|$HOME/.cline"
)

# Harnesses that read ~/.agents/skills natively: "label|marker"
NATIVE_HARNESSES=(
  "Codex|$HOME/.codex"
  "Cursor|$HOME/.cursor"
  "Gemini CLI|$HOME/.gemini"
  "OpenCode|$HOME/.config/opencode"
  "GitHub Copilot|$HOME/.copilot"
)

MODE="install"; LOCAL_SRC=""; DO_LINKS=1; DO_ZIP=1

usage() {
  if [ -f "$0" ]; then sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
  else echo "Usage: bash install.sh [--uninstall] [--local DIR] [--ref REF] [--no-links] [--no-zip]"; fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --uninstall) MODE="uninstall" ;;
    --local) LOCAL_SRC="${2:?--local needs a directory}"; shift ;;
    --ref) REF="${2:?--ref needs a branch or tag}"; shift ;;
    --no-links) DO_LINKS=0 ;;
    --no-zip) DO_ZIP=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

say()  { printf '  %s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

backup() { # move an existing path out of the way instead of deleting it
  local src="$1" dest
  mkdir -p "$BACKUP_ROOT"
  dest="$BACKUP_ROOT/$(basename "$(dirname "$src")")-$(basename "$src")-$(date +%Y%m%d-%H%M%S)"
  local n=1 base="$dest"
  while [ -e "$dest" ] || [ -L "$dest" ]; do dest="$base-$n"; n=$((n + 1)); done
  mv "$src" "$dest"
  say "old copy moved to $dest"
}

is_our_link() { # $1 = path; true if it's a symlink resolving to $TARGET
  [ -L "$1" ] && [ "$(cd "$1" 2>/dev/null && pwd -P)" = "$(cd "$TARGET" 2>/dev/null && pwd -P)" ]
}

check_skill_dir() { # $1 = dir that must hold a valid SKILL.md for this skill
  [ -f "$1/SKILL.md" ] || return 1
  grep -qE "^name:[[:space:]]*${SKILL_NAME}[[:space:]]*$" "$1/SKILL.md"
}

# ---------------------------------------------------------------- uninstall
if [ "$MODE" = "uninstall" ]; then
  echo "Removing skill $SKILL_NAME"
  for h in "${LINK_HARNESSES[@]}"; do
    IFS='|' read -r label dir _ <<<"$h"
    if is_our_link "$dir/$SKILL_NAME" || { [ -L "$dir/$SKILL_NAME" ] && [ ! -e "$dir/$SKILL_NAME" ]; }; then
      rm "$dir/$SKILL_NAME"; ok "$label: link removed"
    fi
  done
  if [ -L "$TARGET" ]; then rm "$TARGET"; ok "symlink $TARGET removed (its target was not touched)"
  elif [ -d "$TARGET" ]; then rm -rf "$TARGET"; ok "$TARGET removed"
  else say "$TARGET not found"; fi
  exit 0
fi

# ---------------------------------------------------------------- fetch
echo "Installing skill $SKILL_NAME v$SKILL_VERSION"
mkdir -p "$AGENTS_DIR"
STAGE="$(mktemp -d "$AGENTS_DIR/.${SKILL_NAME}.tmp.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"
if [ -z "$LOCAL_SRC" ] && [ -n "$SCRIPT_DIR" ] && check_skill_dir "$SCRIPT_DIR" \
   && [ -d "$SCRIPT_DIR/references" ]; then
  LOCAL_SRC="$SCRIPT_DIR"   # running from an unpacked copy of the skill
fi

if [ -n "$LOCAL_SRC" ]; then
  check_skill_dir "$LOCAL_SRC" || die "$LOCAL_SRC does not contain SKILL.md for $SKILL_NAME"
  SRC="$LOCAL_SRC"
  say "source: $SRC"
else
  command -v curl >/dev/null || die "curl is required"
  command -v tar >/dev/null || die "tar is required"
  URL="${MAX_SKILL_TARBALL_URL:-https://codeload.github.com/$REPO/tar.gz/$REF}"
  say "source: github.com/$REPO@$REF"
  mkdir "$STAGE/.dl"
  curl -fsSL --retry 2 "$URL" | tar -xz -C "$STAGE/.dl" 2>/dev/null \
    || die "download failed: $URL (is the repo public and reachable from this network?)"
  # the skill may sit at the repo root or in a subfolder — find its SKILL.md
  SRC=""
  while IFS= read -r f; do
    if check_skill_dir "$(dirname "$f")"; then SRC="$(dirname "$f")"; break; fi
  done < <(find "$STAGE/.dl" -maxdepth 4 -name SKILL.md)
  [ -n "$SRC" ] || die "no SKILL.md with name: $SKILL_NAME in $REPO@$REF"
fi

# copy only what an agent needs: no README, no installer
mkdir "$STAGE/$SKILL_NAME"
cp "$SRC/SKILL.md" "$STAGE/$SKILL_NAME/"
[ -f "$SRC/INSTALL.md" ] && cp "$SRC/INSTALL.md" "$STAGE/$SKILL_NAME/"
[ -d "$SRC/references" ] && cp -R "$SRC/references" "$STAGE/$SKILL_NAME/"
find "$STAGE/$SKILL_NAME" -name .DS_Store -delete
check_skill_dir "$STAGE/$SKILL_NAME" || die "SKILL.md is not the $SKILL_NAME skill — aborting"

# ---------------------------------------------------------------- place into ~/.agents/skills
if [ -e "$TARGET" ] || [ -L "$TARGET" ]; then backup "$TARGET"; fi
mv "$STAGE/$SKILL_NAME" "$TARGET"
ok "installed to $TARGET"

# ---------------------------------------------------------------- symlinks for other harnesses
RESTART=""
if [ "$DO_LINKS" = 1 ]; then
  for h in "${LINK_HARNESSES[@]}"; do
    IFS='|' read -r label dir marker <<<"$h"
    [ -d "$marker" ] || continue
    [ -d "$dir" ] || { mkdir -p "$dir"; RESTART="${RESTART:+$RESTART, }$label"; }
    link="$dir/$SKILL_NAME"
    if [ -L "$link" ]; then rm "$link"
    elif [ -e "$link" ]; then backup "$link"; fi
    ln -s "$TARGET" "$link"
    ok "$label: $link → $TARGET"
  done
fi

for h in "${NATIVE_HARNESSES[@]}"; do
  IFS='|' read -r label marker <<<"$h"
  if [ -d "$marker" ]; then ok "$label: reads $AGENTS_DIR natively"; fi
done

# ---------------------------------------------------------------- zip for Claude apps
if [ "$DO_ZIP" = 1 ]; then
  if command -v zip >/dev/null; then
    ZIP_DIR="${MAX_SKILL_ZIP_DIR:-$HOME/Downloads}"; [ -d "$ZIP_DIR" ] || ZIP_DIR="$HOME"
    ZIP="$ZIP_DIR/$SKILL_NAME-skill.zip"
    rm -f "$ZIP"
    (cd "$AGENTS_DIR" && zip -qr "$ZIP" "$SKILL_NAME" -x "$SKILL_NAME/INSTALL.md" "*/.DS_Store")
    ok "Claude Desktop / Cowork / claude.ai: upload $ZIP in Settings → Skills"
  else
    warn "zip not found — skipped the archive for Claude apps"
  fi
fi

echo
if [ -n "$RESTART" ]; then warn "restart $RESTART — its skills folder was just created"; fi
say "Check: ask your agent \"какие скиллы доступны?\" — max-messenger should be listed."
say "Update: run this script again. Remove: bash install.sh --uninstall"
