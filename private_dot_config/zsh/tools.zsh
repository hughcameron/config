# Tool initializations

# Use emacs keybindings for line editing (EDITOR=nvim triggers vi mode)
bindkey -e

# Custom completions
fpath=(~/.zsh/completions $fpath)

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
