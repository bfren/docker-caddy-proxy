use bf
use conf.nu
use renew.nu [storage_name]

# Remove domain configuration files and certificates for domains no longer defined in conf.json
export def main [
    --live (-l) # Perform deletions (otherwise a dry run is performed)
]: nothing -> nothing {
    if $live {
        bf write "Deletion mode enabled." cleanup
    } else {
        bf write "Dry run mode enabled." cleanup
    }

    let config = conf read
    let opts = $config.opts
    let domains = $config.domains
    let keep = keep_names $config

    # domain configuration files and directories in the sites directory
    let sites_dir = bf env PROXY_SITES
    let site_paths = ls --full-paths $sites_dir
        | get name
        | where {|p| site_name $p | $in not-in ($domains | get primary) }

    # certificate directories in Caddy storage (one directory per host name under certificates/<issuer>/)
    let cert_paths = glob $"($opts.storage)/certificates/*/*"
        | where {|p| ($p | path type) == "dir" and ($p | path basename) not-in $keep }

    let remove = $site_paths | append $cert_paths
    if ($remove | is-empty) {
        bf write ok "Nothing to remove." cleanup
        return
    }

    $remove | each {|p|
        if $live {
            bf write $" .. removing ($p)" cleanup
            rm --force --recursive $p
        } else {
            bf write $" .. will remove ($p)" cleanup
        }
    } | ignore

    bf write ok "Done." cleanup
}

# Return the storage names of every host name in the configuration, including the proxy domain - certificate
# directories with these names are kept (wildcards are stored as wildcard_.<domain>)
export def keep_names [
    config: record  # Configuration from conf read
]: nothing -> list<string> {
    $config.domains
        | each {|d| conf hosts $d }
        | flatten
        | append $config.opts.proxy_domain
        | each {|h| storage_name $h }
}

# Get the domain name from a path in the sites directory (strips .json or .d)
export def site_name [path: string]: nothing -> string {
    $path
        | path basename
        | str replace --regex '\.(json|d)$' ''
}
