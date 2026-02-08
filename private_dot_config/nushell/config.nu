# config.nu
#
# Installed by:
# version = "0.104.1"
#
# This file is used to override default Nushell settings, define
# (or import) custom commands, or run any other startup tasks.
# See https://www.nushell.sh/book/configuration.html
#
# This file is loaded after env.nu and before login.nu
#
# You can open this file in your default editor using:
# config nu
#
# See `help config nu` for more options
#
# You can remove these comments if you want or leave
# them for future reference.

$env.config.buffer_editor = 'hx'
$env.config.show_banner = false


# IMPORTS MODS
use std/formats *
source ~/.config/nushell/scripts/chezmoi.nu
source ~/.config/nushell/scripts/completer.nu
source ~/.config/nushell/scripts/mamba.nu

# IMPORT FUNCTIONS
source ~/.config/nushell/scripts/yazi.nu
source ~/.config/nushell/scripts/helix.nu
source ~/.config/nushell/scripts/clone.nu


# FNM PATH and hooks (env vars are set in env.nu)
if not (which fnm | is-empty) {
    $env.PATH = $env.PATH | prepend ($env.FNM_MULTISHELL_PATH | path join "bin")

    $env.config.hooks.env_change.PWD = (
        $env.config.hooks.env_change.PWD? | append {
            condition: {|| ['.nvmrc' '.node-version'] | any {|el| $el | path exists}}
            code: {|| fnm use}
        }
    )
}

# PATH UPDATES
# $env.PATH = ($env.PATH | append "~/.cargo/bin" | append "/opt/homebrew/bin")
use std/util "path add"
path add $"($nu.home-dir)/.local/bin"
path add $"($nu.home-dir)/.cargo/bin"
path add $"/opt/homebrew/bin"
path add $"($nu.home-dir)/.kit/bin"
path add $"($nu.home-dir)/.config/helix/scripts"


# NUSHELL
launchctl setenv XDG_CONFIG_HOME ~/.config
launchctl setenv XDG_DATA_DIR ~/Library/Caches
alias lscom = nu -c "help commands | to json | vd -f json"

# ZOXIDE
source scripts/zoxide.nu

# CHEZMOI
alias cm = chezmoi
alias cmts = cm-target-to-source
alias cmup = cm-source-update

# HOMEBREW
$env.HOMEBREW_BUNDLE_FILE = '~/.config/homebrew/brewfile.txt'

alias brewup = brew upgrade

def brewcheck [] {
    cm-source-update
}

alias bt = nu ~/.config/nushell/analysis/brewtrend/brewtrend.nu

# STARSHIP
mkdir ($nu.data-dir | path join "vendor/autoload")
$env.STARSHIP_CONFIG = '/Users/hugh/.config/starship/starship.toml'
/opt/homebrew/bin/starship init nu | save -f ($nu.data-dir | path join "vendor/autoload/starship.nu")

# CLAUDE
alias cc = claude
alias ccu = nu ~/.config/nushell/analysis/claude-usage/claude-usage.nu

# NAVI
source ~/.config/nushell/scripts/navi.nu

alias n = navi

# DUCKDB
source ~/.config/nushell/scripts/duckdb.nu

# GCP
alias gcpvm = nu ~/.config/nushell/scripts/gcpvm.nu

# MAMBA
use ~/.config/nushell/scripts/conda.nu

$env.CONDA_NO_PROMPT = true # for Starship prompt

# Helper function to handle conda/mamba activate/deactivate
def conda-mamba-wrapper [...args] {
    if ($args | is-empty) {
        ^mamba
    } else if $args.0 in ["activate" "deactivate"] {
        use ~/.config/nushell/scripts/conda.nu
        if $args.0 == "activate" {
            if ($args | length) > 1 {
                conda activate $args.1
            } else {
                conda activate
            }
        } else {
            conda deactivate
        }
    } else {
        ^mamba ...$args
    }
}

# Wrapper for conda that redirects activate/deactivate to conda.nu module
def --wrapped conda [...args] {
    conda-mamba-wrapper ...$args
}

# Wrapper for mamba that redirects activate/deactivate to conda.nu module
def --wrapped mamba [...args] {
    conda-mamba-wrapper ...$args
}

# Aliases for conda/mamba activation using the conda.nu module
alias va = conda activate
alias vda = conda deactivate

# FINDER
alias peek = ^open .

# TERMINAL
alias tap = ^open -a Terminal

# GIT
alias lg = lazygit

# OPENCLAW
alias oc = openclaw tui

# MSGVAULT
alias em = msgvault

# SESSIONS
def q [query: string] {
    qmd search $query -c sessions
}
