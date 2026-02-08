# Get the new IP from gcloud
let gcloud_output = (gcloud cloud-shell ssh --dry-run)
let ssh_line = ($gcloud_output | lines | where $it =~ 'hugh_cameron@' | first)

if ($ssh_line | is-empty) {
    print "Could not find a line with 'hugh_cameron@' in gcloud output:"
    print $gcloud_output
    exit 1
}

let parsed = ($ssh_line | parse -r 'hugh_cameron@(\d+\.\d+\.\d+\.\d+)')

if ($parsed | is-empty) {
    print "Could not extract IP address from the gcloud output line:"
    print $ssh_line
    exit 1
}

let new_ip = ($parsed | get capture0 | get 0)


# Path to your SSH config
let config_path = ($nu.home-path | path join '.ssh/config')

# Read the config file
let config_lines = (open $config_path | lines)

# Find the line number for 'Host gcp'
let host_idx = ($config_lines | enumerate | where item =~ '^Host gcp$' | get index | first)

if ($host_idx | is-empty) {
    print "Could not find 'Host gcp' in SSH config."
    exit 1
}

# Find the next 'Hostname' line after 'Host gcp'
let hostname_lines = (
    $config_lines
    | enumerate
    | skip ($host_idx + 1)
    | where item =~ '^\s*Hostname '
)

let hostname_idx = if ($hostname_lines | is-empty) {
    null
} else {
    $hostname_lines | get index | first
}

if ($hostname_idx | is-empty) {
    print "Could not find 'Hostname' line after 'Host gcp'."
    exit 1
}

# Update the Hostname line
let updated_lines = (
    $config_lines
    | enumerate
    | each {|row|
        if $row.index == $hostname_idx {
            $"Hostname ($new_ip)"
        } else {
            $row.item
        }
    }
)

# Write back to the config file
$updated_lines | str join (char nl) | save --force $config_path
