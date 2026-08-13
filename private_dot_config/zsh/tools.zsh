# Tool initializations

# Use emacs keybindings for line editing (EDITOR=nvim triggers vi mode)
bindkey -e

# Custom completions
fpath=(~/.zsh/completions $fpath)

# z-async: zsh-autocomplete's async engine. Upstream ships it as a git submodule,
# but Homebrew builds from the GitHub source tarball, which excludes submodules —
# so the brew package is missing share/zsh-autocomplete/z-async entirely. Without
# it, every prompt errors with "z-async: function definition file not found" and
# live completion silently never runs. Cloned separately by
# run_onchange_install-z-async.sh; prepending here lets autoload find it.
[[ -d ~/.local/share/z-async ]] && fpath=(~/.local/share/z-async $fpath)

# zsh-autocomplete: real-time type-ahead completion (replaces manual compinit)
# Must be sourced before any compdef calls (e.g. carapace)
if [[ -f /opt/homebrew/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh ]]; then
    source /opt/homebrew/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh
elif [[ -f /home/linuxbrew/.linuxbrew/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh ]]; then
    source /home/linuxbrew/.linuxbrew/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh
else
    # Fallback: manual compinit if zsh-autocomplete not installed
    autoload -Uz compinit && compinit
fi

# Starship prompt
eval "$(starship init zsh)"

# Zoxide (provides z and zi commands)
eval "$(zoxide init zsh)"

# FNM - Fast Node Manager with auto version switching
command -v fnm &>/dev/null && eval "$(fnm env --use-on-cd --shell zsh)"

# fzf key bindings (Ctrl+R history, Ctrl+T file picker, Alt+C cd)
eval "$(fzf --zsh)"

# Carapace completions
command -v carapace &>/dev/null && eval "$(carapace _carapace zsh)"

# Last-resort completion: ask the command what it supports. Anything with no
# completion function of its own and no carapace spec would otherwise fall
# through to bare filenames, even where it wants a subcommand — this parses
# `cmd --help` for its subcommands and flags instead. Must come after carapace
# so real specs still win. See ~/.zsh/completions/_help_generic.
autoload -Uz _help_generic
compdef _help_generic -default-
