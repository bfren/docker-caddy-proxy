use bf
use generate.nu
use reload.nu

# How often to check for changes - polling is used (rather than file system events) because events are not
# reliably passed through to containers from bind-mounted volumes, e.g. on Docker Desktop
export const interval = 5sec

# Return a fingerprint of the configuration files (paths, sizes and modified times) - it changes when any of them do
export def fingerprint [
    files: record   # Paths to conf.json (conf), users.json (users) and the sites directory (sites)
]: nothing -> string {
    [$files.conf $files.users]
        | append (glob $"($files.sites)/*.json")
        | append (glob $"($files.sites)/*.d/*.json")
        | where {|p| $p | path exists }
        | each {|p|
            # use numbers - converting dates to strings gives relative times ('5 seconds ago') which keep changing
            let file = ls --full-paths $p | first
            $"($file.name)|($file.size | into int)|($file.modified | into int)"
        }
        | sort
        | str join (char newline)
        | hash md5
}

# Regenerate configuration and reload Caddy - an invalid change is reported and the current configuration is kept
export def apply []: nothing -> nothing {
    try {
        generate
        bf ch apply_file "20-proxy"
        reload
    } catch {
        bf write notok "Configuration has not been reloaded - fix the errors above and save again." autoreload
    }
}

# Watch conf.json, users.json and the sites directory, and regenerate and reload configuration when they change
export def main []: nothing -> nothing {
    bf env load
    bf env x_set --override autoreload

    let files = {conf: (bf env PROXY_CONF), users: (bf env PROXY_USERS), sites: (bf env PROXY_SITES)}
    bf write $"Watching ($files | values | str join ', ') for changes." autoreload

    mut last = fingerprint $files
    loop {
        sleep $interval
        let current = fingerprint $files
        if $current == $last { continue }

        # wait until files have stopped changing (e.g. while an editor saves several files)
        sleep $interval
        if (fingerprint $files) != $current { continue }

        bf write "Configuration has changed - regenerating." autoreload
        apply

        # take the fingerprint again because regenerating rewrites generated files in the sites directory
        $last = fingerprint $files
    }
}
