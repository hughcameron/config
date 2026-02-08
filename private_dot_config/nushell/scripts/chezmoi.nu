# Chezmoi utility functions

# Update chezmoi source files from their target locations
# This function parses the output of `cm diff | grep 'diff --git'` and
# copies the modified files from their target locations to the chezmoi source
export def "cm-target-to-source" [] {
    let chezmoi_source = "/Users/hugh/github/hughcameron/config"
    let home = $env.HOME

    mut has_updates = false

    # Get the list of files with differences
    let diff_output = (chezmoi diff | grep 'diff --git')

    if ($diff_output | is-empty) {
        print "No differences found between chezmoi source and target files"
        return false
    }

    # Parse each diff line to extract the file path
    let files = ($diff_output | lines | each { |line|
        # Extract the path after 'b/' in the diff output
        # Format: "diff --git a/.config/nushell/config.nu b/.config/nushell/config.nu"
        let parts = ($line | split row ' ')
        let file_path = ($parts | get 3 | str substring 2..)  # Remove 'b/' prefix
        $file_path
    })

    print $"Found ($files | length) files with differences:"
    $files | each { |f| print $"  - ($f)" }
    print ""

    # Update each file using chezmoi re-add
    for file in $files {
        let target_path = ($home | path join $file)

        print $"Re-adding: ($file)"

        # Check if target file exists
        if not ($target_path | path exists) {
            print $"  WARNING: Target file does not exist: ($target_path)"
            continue
        }

        # Use chezmoi re-add to update the source
        chezmoi re-add $target_path
        if $env.LAST_EXIT_CODE == 0 {
            print $"  ✓ Re-added ($target_path)"
            $has_updates = true
        } else {
            print $"  ❌ Error re-adding ($target_path)"
        }
    }

    $has_updates
}

# Dump Homebrew packages to brewfile
export def "cm-dump-brewfile" [] {
    print "Dumping Homebrew packages to brewfile..."
    ^brew bundle dump --force $"--file=($env.HOME)/.config/homebrew/brewfile.txt"
    print "✓ Brewfile updated"
}

# Comprehensive chezmoi source update: dump brewfile and re-add modified files
export def "cm-source-update" [] {
    # 1. Dump brewfile
    cm-dump-brewfile

    # 2. Re-add modified files
    let diff_updates = (cm-target-to-source)

    # 3. Open lazygit
    print "Opening lazygit in chezmoi source..."
    cd ~/github/hughcameron/config
    ^lazygit
}
