#!/bin/bash
# Install z-async, the async engine zsh-autocomplete depends on.
#
# Upstream zsh-autocomplete vendors z-async as a git submodule. Homebrew builds
# from the GitHub source tarball, which omits submodules, so both the darwin and
# linuxbrew packages ship without share/zsh-autocomplete/z-async. The result:
# two "z-async: function definition file not found" errors on every prompt and
# no live type-ahead completion at all.
#
# Cloning it here and prepending ~/.local/share/z-async to fpath (see
# private_dot_config/zsh/tools.zsh) satisfies the plugin's `autoload -Uz z-async`
# without patching Homebrew's pkgshare, which brew upgrades would overwrite.
#
# hash: 2026-08-04-v1

set -euo pipefail

dest="$HOME/.local/share/z-async"

if [[ -d "$dest/.git" ]]; then
  echo "Updating z-async in $dest..."
  git -C "$dest" pull --quiet --ff-only
else
  echo "Cloning z-async into $dest..."
  mkdir -p "$(dirname "$dest")"
  git clone --quiet https://github.com/marlonrichert/z-async "$dest"
fi

echo "Done."
