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
