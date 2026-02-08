def --env clone [url: string] {
    # Helper function to display a block-character progress bar
    def show-progress [percent: int, label: string] {
        let width = 50
        let blocks = ["" "▏" "▎" "▍" "▌" "▋" "▊" "▉" "█"]
        let filled = ($width * $percent / 100)
        let full_blocks = ($filled | math floor)
        let remainder = (($filled - $full_blocks) * 8 | math floor)

        let filled_bar = (0..$full_blocks | each { "█" } | str join)
        let partial = if $remainder > 0 { $blocks | get $remainder } else { "" }
        let empty_count = ($width - $full_blocks - (if $remainder > 0 { 1 } else { 0 }))
        let empty_bar = (0..$empty_count | each { "▒" } | str join)

        let bar = $"($filled_bar)($partial)($empty_bar)"
        let percent_str = $"($percent | fill -a r -w 3)%"
        print -n $"\r($percent_str) ($bar) ($label | str trim | str substring ..30)"
    }

    # Support owner/repo shorthand
    let parsed = if ($url =~ '^([\w.-]+)/([\w.-]+)$') {
        {
            owner: ($url | str replace -r '^([\w.-]+)/([\w.-]+)$' '$1'),
            repo: ($url | str replace -r '^([\w.-]+)/([\w.-]+)$' '$2'),
            full_url: ($url | str replace -r '^([\w.-]+)/([\w.-]+)$' 'https://github.com/$1/$2')
        }
    } else if ($url =~ '^https?://github.com/([^/]+)/([^/]+?)(?:\.git)?$') {
        {
            owner: ($url | str replace -r '^https?://github.com/([^/]+)/([^/]+?)(?:\\.git)?$' '$1'),
            repo: ($url | str replace -r '^https?://github.com/([^/]+)/([^/]+?)(?:\\.git)?$' '$2'),
            full_url: $url
        }
    } else if ($url =~ '^git@github\.com:([^/]+)/([^/]+?)(?:\\.git)?$') {
        {
            owner: ($url | str replace -r '^git@github\\.com:([^/]+)/([^/]+?)(?:\\.git)?$' '$1'),
            repo: ($url | str replace -r '^git@github\\.com:([^/]+)/([^/]+?)(?:\\.git)?$' '$2'),
            full_url: $url
        }
    } else {
        print $"Invalid GitHub URL format: ($url)"
        return
    }

    let owner = $parsed.owner
    let repo = $parsed.repo
    let url_to_clone = $parsed.full_url
    let target_dir = $"($env.HOME)/github/($owner)/($repo)"

    if ($target_dir | path exists) {
        let action = [
            "Open in editor",
            "Delete and re-clone",
            "Cancel"
        ] | input list $"Repository '($target_dir)' already exists."

        match $action {
            "Open in editor" => {
                cd $target_dir
                ^yazi .
                return
            }
            "Delete and re-clone" => {
                print $"Deleting '($target_dir)'..."
                rm -rf $target_dir
            }
            "Cancel" => {
                print "Operation cancelled."
                return
            }
        }
    }

    print $"Cloning '($owner)/($repo)' into '($target_dir)'"
    mkdir $"($env.HOME)/github/($owner)"

    ^gh repo clone $url_to_clone $target_dir -- --progress

    if $env.LAST_EXIT_CODE == 0 {
        print "Clone complete. Opening in editor..."
        cd $target_dir
        ^yazi .
    } else {
        print $"Failed to clone repository. Exit code: ($env.LAST_EXIT_CODE)"
    }
}
