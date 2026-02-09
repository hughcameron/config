#!/bin/bash
# Config Housekeeping — run daily by launchd, reviewed by Carson at session start
# Collects brew bundle state, chezmoi drift, and system config changes
# Output: ~/.config/carson/housekeeping-report.txt

set -euo pipefail

REPORT_DIR="$HOME/.config/carson"
REPORT_FILE="$REPORT_DIR/housekeeping-report.txt"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

mkdir -p "$REPORT_DIR"

# Start report
cat > "$REPORT_FILE" <<EOF
# Config Housekeeping Report
# Generated: $TIMESTAMP
# ─────────────────────────────────────────
EOF

# ── 1. Brew Bundle Dump ──────────────────────────────────────────────
{
  echo ""
  echo "## Brew Bundle Dump"
  echo ""

  DUMP_FILE="$REPORT_DIR/brewfile-dump.txt"
  if command -v brew &>/dev/null; then
    brew bundle dump --file="$DUMP_FILE" --force 2>/dev/null
    echo "Dumped to: $DUMP_FILE"
    echo "Package count: $(wc -l < "$DUMP_FILE" | tr -d ' ')"

    # Compare against chezmoi-managed brewfile (rendered version)
    MANAGED_BREWFILE="$HOME/.config/homebrew/brewfile.txt"
    if [ -f "$MANAGED_BREWFILE" ]; then
      DIFF_OUTPUT=$(diff --unified=0 "$MANAGED_BREWFILE" "$DUMP_FILE" 2>/dev/null || true)
      if [ -n "$DIFF_OUTPUT" ]; then
        echo ""
        echo "### Drift detected vs managed Brewfile:"
        echo '```'
        echo "$DIFF_OUTPUT"
        echo '```'
      else
        echo "Status: IN SYNC with managed Brewfile"
      fi
    else
      echo "Warning: No managed Brewfile found at $MANAGED_BREWFILE"
    fi
  else
    echo "Status: brew not found (expected on Linux)"
  fi
} >> "$REPORT_FILE"

# ── 2. Chezmoi Drift ────────────────────────────────────────────────
{
  echo ""
  echo "## Chezmoi Status"
  echo ""

  if command -v chezmoi &>/dev/null; then
    STATUS_OUTPUT=$(chezmoi status 2>/dev/null || true)
    if [ -n "$STATUS_OUTPUT" ]; then
      echo "### Files out of sync:"
      echo '```'
      echo "$STATUS_OUTPUT"
      echo '```'
      echo ""
      echo "### Diff summary:"
      echo '```'
      chezmoi diff --no-pager 2>/dev/null | head -100 || true
      echo '```'
    else
      echo "Status: ALL IN SYNC"
    fi
  else
    echo "Status: chezmoi not found"
  fi
} >> "$REPORT_FILE"

# ── 3. Git Status of Config Repo ────────────────────────────────────
{
  echo ""
  echo "## Config Repo Git Status"
  echo ""

  CONFIG_REPO="$(chezmoi source-path 2>/dev/null || echo "$HOME/github/hughcameron/config")"
  if [ -d "$CONFIG_REPO/.git" ]; then
    echo "Repo: $CONFIG_REPO"
    echo '```'
    git -C "$CONFIG_REPO" status --short 2>/dev/null || true
    echo '```'
    echo ""
    echo "Last commit:"
    echo '```'
    git -C "$CONFIG_REPO" log --oneline -3 2>/dev/null || true
    echo '```'
  else
    echo "Warning: Config repo not found at $CONFIG_REPO"
  fi
} >> "$REPORT_FILE"

# ── 4. Summary ──────────────────────────────────────────────────────
{
  echo ""
  echo "## Summary"
  echo ""

  BREW_DRIFT="none"
  CHEZMOI_DRIFT="none"
  GIT_DIRTY="clean"

  if command -v brew &>/dev/null; then
    MANAGED_BREWFILE="$HOME/.config/homebrew/brewfile.txt"
    DUMP_FILE="$REPORT_DIR/brewfile-dump.txt"
    if [ -f "$MANAGED_BREWFILE" ] && [ -f "$DUMP_FILE" ]; then
      if ! diff -q "$MANAGED_BREWFILE" "$DUMP_FILE" &>/dev/null; then
        BREW_DRIFT="DRIFTED"
      fi
    fi
  fi

  if command -v chezmoi &>/dev/null; then
    if [ -n "$(chezmoi status 2>/dev/null)" ]; then
      CHEZMOI_DRIFT="DRIFTED"
    fi
  fi

  CONFIG_REPO="$(chezmoi source-path 2>/dev/null || echo "$HOME/github/hughcameron/config")"
  if [ -d "$CONFIG_REPO/.git" ]; then
    if [ -n "$(git -C "$CONFIG_REPO" status --porcelain 2>/dev/null)" ]; then
      GIT_DIRTY="DIRTY"
    fi
  fi

  echo "- Brew bundle: $BREW_DRIFT"
  echo "- Chezmoi sync: $CHEZMOI_DRIFT"
  echo "- Config repo: $GIT_DIRTY"
  echo ""

  if [ "$BREW_DRIFT" = "none" ] && [ "$CHEZMOI_DRIFT" = "none" ] && [ "$GIT_DIRTY" = "clean" ]; then
    echo "ALL CLEAR - no action needed"
  else
    echo "ACTION REQUIRED - Carson should review at next session"
  fi
} >> "$REPORT_FILE"

echo "Housekeeping report written to $REPORT_FILE"
