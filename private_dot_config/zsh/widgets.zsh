# Zle widgets and keybindings

# Disable XON/XOFF flow control so Ctrl+S reaches applications (e.g. nvim)
stty -ixon

# Ctrl+Y: Yazi with CWD tracking and prompt refresh
_yazi_widget() {
    local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
    command yazi --cwd-file="$tmp"
    IFS= read -r cwd < "$tmp"
    [[ -n "$cwd" ]] && [[ "$cwd" != "$PWD" ]] && [[ -d "$cwd" ]] && cd -- "$cwd"
    rm -f -- "$tmp"
    zle reset-prompt
}
zle -N _yazi_widget
bindkey '^y' _yazi_widget

# Ctrl+K: Neovim editor
_nvim_widget() {
    command nvim
    zle reset-prompt
}
zle -N _nvim_widget
bindkey '^k' _nvim_widget

# Ctrl+G: Navi cheatsheet snippet insertion
_navi_widget() {
    local input="$BUFFER"
    local last_command
    last_command="$(echo "$input" | navi fn widget::last_command)"

    local result
    if [[ -z "$last_command" ]]; then
        result="$(navi --print)"
    else
        result="$(navi --print --query "$last_command")"
    fi

    if [[ -n "$result" ]]; then
        BUFFER="$result"
        CURSOR=${#result}
    fi
    zle reset-prompt
}
zle -N _navi_widget
bindkey '^g' _navi_widget

# Ctrl+O: Lazygit
_lazygit_widget() {
    command lazygit
    zle reset-prompt
}
zle -N _lazygit_widget
bindkey '^o' _lazygit_widget

# Ctrl+E: Edit current command line in nvim
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^e' edit-command-line

# Ctrl+B: Decision register browser (fzf + glow)
_decisions_widget() {
    decisions
    zle reset-prompt
}
zle -N _decisions_widget
bindkey '^b' _decisions_widget
