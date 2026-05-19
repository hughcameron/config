# Shell functions

# Yazi file manager with CWD tracking on exit
# https://yazi-rs.github.io/docs/quick-start/#shell-wrapper
y() {
    local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
    command yazi "$@" --cwd-file="$tmp"
    IFS= read -r cwd < "$tmp"
    [[ -n "$cwd" ]] && [[ "$cwd" != "$PWD" ]] && [[ -d "$cwd" ]] && cd -- "$cwd"
    rm -f -- "$tmp"
}

# Launch a 4-window tmux workspace (claude / nvim / lazygit / yazi) in a directory.
# Usage: lab [dir]   — defaults to $PWD. Session name = directory basename.
# Reattaches if a session with that name already exists; each window drops to a
# shell when its tool exits.
lab() {
    local dir="${1:-$PWD}"
    dir="${dir:A}"
    if [[ ! -d "$dir" ]]; then
        print -u2 "lab: not a directory: $dir"
        return 1
    fi
    local name="${dir:t}"
    local shell="${SHELL:-/bin/zsh}"
    local claude_perms="--dangerously-skip-permissions"
    [[ "$(uname -s)" == "Darwin" ]] && claude_perms="--permission-mode auto"

    if ! tmux has-session -t="$name" 2>/dev/null; then
        tmux new-session -d -s "$name" -c "$dir" -n claude  "claude $claude_perms; exec $shell"
        tmux new-window  -t "$name:" -c "$dir" -n nvim     "nvim; exec $shell"
        tmux new-window  -t "$name:" -c "$dir" -n lazygit  "lazygit; exec $shell"
        tmux new-window  -t "$name:" -c "$dir" -n yazi     "yazi; exec $shell"
    fi
    tmux select-window -t "$name:claude" 2>/dev/null

    if [[ -n "$TMUX" ]]; then
        tmux switch-client -t "$name"
    else
        tmux attach -t "$name"
    fi
}

# fzf picker for tmux sessions: switch (inside tmux) or attach (outside).
ta() {
    local session
    session=$(tmux list-sessions -F '#{session_name}' 2>/dev/null \
        | fzf --prompt='tmux > ' --height=40% --reverse --no-multi) || return
    [[ -z "$session" ]] && return
    if [[ -n "$TMUX" ]]; then
        tmux switch-client -t "$session"
    else
        tmux attach -t "$session"
    fi
}

# Smart GitHub clone with shorthand support (owner/repo)
clone() {
    local url="$1"
    local owner repo url_to_clone target_dir

    if [[ "$url" =~ '^([a-zA-Z0-9._-]+)/([a-zA-Z0-9._-]+)$' ]]; then
        owner="$match[1]"
        repo="$match[2]"
        url_to_clone="https://github.com/${owner}/${repo}"
    elif [[ "$url" =~ '^https?://github\.com/([^/]+)/([^/]+)$' ]]; then
        owner="$match[1]"
        repo="$match[2]"
        repo="${repo%.git}"
        url_to_clone="$url"
    elif [[ "$url" =~ '^git@github\.com:([^/]+)/([^/]+)$' ]]; then
        owner="$match[1]"
        repo="$match[2]"
        repo="${repo%.git}"
        url_to_clone="$url"
    else
        echo "Invalid GitHub URL format: $url"
        return 1
    fi

    target_dir="$HOME/github/${owner}/${repo}"

    if [[ -d "$target_dir" ]]; then
        echo "Repository '$target_dir' already exists."
        echo "1) Open in nvim"
        echo "2) Delete and re-clone"
        echo "3) Cancel"
        read -r "choice?Choose [1-3]: "
        case "$choice" in
            1) cd "$target_dir" && nvim . ; return ;;
            2) echo "Deleting '$target_dir'..." ; rm -rf "$target_dir" ;;
            3) echo "Operation cancelled." ; return ;;
            *) echo "Invalid choice." ; return 1 ;;
        esac
    fi

    echo "Cloning '${owner}/${repo}' into '${target_dir}'"
    mkdir -p "$HOME/github/${owner}"

    if gh repo clone "$url_to_clone" "$target_dir" -- --progress; then
        echo "Clone complete. Opening in nvim..."
        cd "$target_dir" && nvim .
    else
        echo "Failed to clone repository."
        return 1
    fi
}

# Chezmoi: re-add modified files from target to source
cm-target-to-source() {
    local has_updates=false
    local diff_output
    diff_output="$(chezmoi diff | grep 'diff --git')"

    if [[ -z "$diff_output" ]]; then
        echo "No differences found between chezmoi source and target files"
        return 0
    fi

    local files=()
    while IFS= read -r line; do
        local file_path
        file_path="$(echo "$line" | awk '{print $4}' | sed 's|^b/||')"
        files+=("$file_path")
    done <<< "$diff_output"

    echo "Found ${#files[@]} files with differences:"
    for f in "${files[@]}"; do
        echo "  - $f"
    done
    echo ""

    for file in "${files[@]}"; do
        local target_path="$HOME/$file"
        echo "Re-adding: $file"

        if [[ ! -f "$target_path" ]]; then
            echo "  WARNING: Target file does not exist: $target_path"
            continue
        fi

        if chezmoi re-add "$target_path"; then
            echo "  Re-added $target_path"
            has_updates=true
        else
            echo "  Error re-adding $target_path"
        fi
    done

    $has_updates
}

# Chezmoi: dump brew bundle to brewfile
cm-dump-brewfile() {
    echo "Dumping Homebrew packages to brewfile..."
    brew bundle dump --force "--file=$HOMEBREW_BUNDLE_FILE"
    echo "Brewfile updated"
}

# Chezmoi: full source update with lazygit
cm-source-update() {
    cm-dump-brewfile
    cm-target-to-source
    echo "Opening lazygit in chezmoi source..."
    (cd "$HOME/github/hughcameron/config" && lazygit)
}

# QMD session search
q() {
    qmd search "$1" -c sessions
}

# Decision register browser (MADR files in decisions/)
# Usage: decisions [--all]
decisions() {
    local search_dirs=()

    if [[ "$1" == "--all" ]]; then
        for repo in "$HOME"/github/*/*/decisions(N/); do
            search_dirs+=("$repo")
        done
    else
        # Find decisions/ in current repo (walk up to git root)
        local git_root
        git_root="$(git rev-parse --show-toplevel 2>/dev/null)"
        if [[ -n "$git_root" && -d "$git_root/decisions" ]]; then
            search_dirs+=("$git_root/decisions")
        else
            echo "No decisions/ directory found in current repo."
            echo "Use 'decisions --all' to browse all repos."
            return 1
        fi
    fi

    # Build the list: extract id, title, date from frontmatter
    # Format: display text<TAB>filepath (tab-separated, filepath hidden in fzf)
    local entries=()
    for dir in "${search_dirs[@]}"; do
        local repo_name="$(basename "$(dirname "$dir")")"
        for f in "$dir"/*.md(N); do
            local id title date_created
            id="$(basename "$f" .md | cut -d- -f1)"
            title="$(grep '^# ' "$f" | head -1 | sed 's/^# [0-9]*\. //')"
            date_created="$(grep '^date-created:' "$f" | head -1 | sed 's/date-created: //')"
            if [[ "$1" == "--all" ]]; then
                entries+=("$id │ $date_created │ $repo_name │ $title"$'\t'"$f")
            else
                entries+=("$id │ $date_created │ $title"$'\t'"$f")
            fi
        done
    done

    if [[ ${#entries[@]} -eq 0 ]]; then
        echo "No decisions found."
        return 1
    fi

    # fzf with glow preview — tab separates display from filepath
    local selected
    selected="$(printf '%s\n' "${entries[@]}" | \
        fzf --ansi \
            --header 'Decision Register (Enter: open in editor, Esc: close)' \
            --preview 'CLICOLOR_FORCE=1 glow -w $(( COLUMNS / 2 - 4 )) -s dark {2}' \
            --preview-window 'right:60%:wrap' \
            --delimiter $'\t' \
            --with-nth 1)"

    if [[ -n "$selected" ]]; then
        local file_path="${selected##*$'\t'}"
        ${EDITOR:-nvim} "$file_path"
    fi
}

# YDF CLI (Linux only): install/update from latest v* GitHub release.
# Layout: ~/.local/share/ydf/<version>/ with a 'current' symlink, and
# prefixed shims (ydf-train, ydf-evaluate, ...) in ~/.local/bin.
ydf-update() {
    if [[ "$(uname -s)" != "Linux" ]]; then
        echo "ydf-update: CLI binaries only ship for Linux."
        return 1
    fi

    local repo="google/yggdrasil-decision-forests"
    local share_dir="$HOME/.local/share/ydf"
    local bin_dir="$HOME/.local/bin"

    local latest
    latest="$(gh release list --repo "$repo" --limit 30 \
        --json tagName --jq '[.[] | select(.tagName | test("^v[0-9]"))][0].tagName')"
    if [[ -z "$latest" ]]; then
        echo "ydf-update: no v* CLI release found."
        return 1
    fi

    local installed=""
    [[ -L "$share_dir/current" ]] && installed="$(basename "$(readlink "$share_dir/current")")"
    if [[ "$installed" == "$latest" && "$1" != "--force" ]]; then
        echo "ydf-update: already on $latest (--force to reinstall)."
        return 0
    fi

    local target_dir="$share_dir/$latest"
    local tmp_zip; tmp_zip="$(mktemp -t ydf-XXXXXX.zip)"

    echo "ydf-update: downloading $latest..."
    if ! gh release download "$latest" --repo "$repo" \
            --pattern 'cli_linux.zip' --output "$tmp_zip" --clobber; then
        rm -f "$tmp_zip"
        echo "ydf-update: download failed."
        return 1
    fi

    mkdir -p "$target_dir"
    unzip -q -o "$tmp_zip" -d "$target_dir"
    rm -f "$tmp_zip"
    chmod +x "$target_dir"/*(.N)

    ln -sfn "$target_dir" "$share_dir/current"

    mkdir -p "$bin_dir"
    for old in "$bin_dir"/ydf-*(N@); do
        [[ "$(readlink "$old")" == "$share_dir/"* ]] && rm -f "$old"
    done
    for bin in "$target_dir"/*(.N); do
        ln -sfn "$share_dir/current/${bin:t}" "$bin_dir/ydf-${bin:t}"
    done

    echo "ydf-update: installed $latest -> $target_dir"
    print -l "$target_dir"/*(.N:t) | sed 's/^/  ydf-/'
}

# List every callable name in the current shell: external commands,
# aliases, functions, and builtins (sorted, deduped across categories).
lscmd() {
    print -rl -- ${(ko)commands} ${(ko)aliases} ${(ko)functions} ${(ko)builtins} | sort -u
}

# Copy stdin to the system clipboard. Uses pbcopy on macOS; on Linux emits an
# OSC 52 escape sequence so the *local* terminal (via SSH + tmux passthrough)
# receives the data — tmux.conf has set-clipboard on + allow-passthrough on.
c() {
    if (( $+commands[pbcopy] )); then
        pbcopy
        return
    fi
    local data
    data="$(base64 | tr -d '\n')"
    printf '\033]52;c;%s\a' "$data" > /dev/tty
}
