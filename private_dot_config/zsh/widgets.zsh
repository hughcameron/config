# Zle widgets and keybindings

# Ctrl+F: Yazi with CWD tracking and prompt refresh
_yazi_widget() {
    local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
    command yazi --cwd-file="$tmp"
    IFS= read -r cwd < "$tmp"
    [[ -n "$cwd" ]] && [[ "$cwd" != "$PWD" ]] && [[ -d "$cwd" ]] && cd -- "$cwd"
    rm -f -- "$tmp"
    zle reset-prompt
}
zle -N _yazi_widget
bindkey '^f' _yazi_widget

# Ctrl+K: Helix editor
_hx_widget() {
    command hx
    zle reset-prompt
}
zle -N _hx_widget
bindkey '^k' _hx_widget

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

# Ctrl+B: Backlog board
_backlog_board_widget() {
    command backlog board
    zle reset-prompt
}
zle -N _backlog_board_widget
bindkey '^b' _backlog_board_widget
