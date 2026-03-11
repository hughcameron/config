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
        echo "1) Open in yazi"
        echo "2) Delete and re-clone"
        echo "3) Cancel"
        read -r "choice?Choose [1-3]: "
        case "$choice" in
            1) cd "$target_dir" && yazi . ; return ;;
            2) echo "Deleting '$target_dir'..." ; rm -rf "$target_dir" ;;
            3) echo "Operation cancelled." ; return ;;
            *) echo "Invalid choice." ; return 1 ;;
        esac
    fi

    echo "Cloning '${owner}/${repo}' into '${target_dir}'"
    mkdir -p "$HOME/github/${owner}"

    if gh repo clone "$url_to_clone" "$target_dir" -- --progress; then
        echo "Clone complete. Opening in yazi..."
        cd "$target_dir" && yazi .
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
    local repos=(
        "$HOME/github/hughcameron/ops"
        "$HOME/github/hughcameron/mavericks"
        "$HOME/github/hughcameron/condor"
        "$HOME/github/hughcameron/stryker"
    )

    if [[ "$1" == "--all" ]]; then
        for repo in "${repos[@]}"; do
            [[ -d "$repo/decisions" ]] && search_dirs+=("$repo/decisions")
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
    local entries=()
    for dir in "${search_dirs[@]}"; do
        local repo_name="$(basename "$(dirname "$dir")")"
        for f in "$dir"/*.md(N); do
            local id title date_created
            id="$(basename "$f" .md | cut -d- -f1)"
            # Extract title from H1 line
            title="$(grep '^# ' "$f" | head -1 | sed 's/^# [0-9]*\. //')"
            # Extract date-created from frontmatter
            date_created="$(grep '^date-created:' "$f" | head -1 | sed 's/date-created: //')"
            if [[ "$1" == "--all" ]]; then
                entries+=("$(printf "%-4s │ %-10s │ %-12s │ %s" "$id" "$date_created" "$repo_name" "$title")"$'\t'"$f")
            else
                entries+=("$(printf "%-4s │ %-10s │ %s" "$id" "$date_created" "$title")"$'\t'"$f")
            fi
        done
    done

    if [[ ${#entries[@]} -eq 0 ]]; then
        echo "No decisions found."
        return 1
    fi

    # fzf with glow preview
    local selected
    selected="$(printf '%s\n' "${entries[@]}" | \
        column -t -s $'\t' | \
        fzf --ansi \
            --header 'Decision Register (Enter: open in editor, Esc: close)' \
            --preview 'echo {} | sed "s/.*\t//" | xargs glow -w $(( COLUMNS / 2 - 4 )) -s dark' \
            --preview-window 'right:60%:wrap' \
            --delimiter $'\t' \
            --with-nth 1)"

    if [[ -n "$selected" ]]; then
        local file_path
        file_path="$(echo "$selected" | sed 's/.*\t//')"
        ${EDITOR:-hx} "$file_path"
    fi
}
