use bf
use bf-s6
use conf.nu

# Delete certificates from Caddy storage and restart Caddy, so it requests new ones
export def main [
    --all (-a)                  # Renew all certificates
    --domain (-d): string = ""  # Only renew certificates for this domain (its primary and aliases)
]: nothing -> nothing {
    if not (check_args $all $domain) { bf write error "Either --all or --domain must be set (but not both)." renew }

    let config = conf read
    let opts = $config.opts

    # an empty list of hosts matches every certificate
    let hosts = if $all { [] } else if $domain == $opts.proxy_domain { [$domain] } else {
        let d = $config.domains | where primary == $domain
        if ($d | is-empty) { bf write error $"Domain ($domain) is not defined in conf.json." renew }
        conf hosts ($d | first)
    }

    let dirs = cert_dirs $opts.storage $hosts
    if ($dirs | is-empty) {
        bf write ok "No certificates to remove." renew
        return
    }

    $dirs | each {|p|
        bf write $" .. removing ($p)" renew
        rm --force --recursive $p
    } | ignore

    # Caddy keeps certificates in memory, so it must be restarted (reloading is not enough)
    if (bf-s6 svc is_up caddy) {
        if $opts.live { bf write notok "Requesting live certificates - check Let's Encrypt rate limits." renew }
        bf-s6 svc restart caddy
        bf write ok "Caddy restarted - new certificates will be requested (see the container log)." renew
    } else {
        bf write ok "Caddy is not running - new certificates will be requested when it starts." renew
    }
}

# Returns true if exactly one of --all and --domain is set, so all certificates are only renewed when asked for
export def check_args [
    all: bool       # Value of --all
    domain: string  # Value of --domain
]: nothing -> bool {
    $all != ($domain != "")
}

# Return certificate directories in Caddy storage for the given host names (all certificates if empty) -
# there is one directory per host name under certificates/<issuer>/
export def cert_dirs [
    storage: string         # Caddy storage directory
    hosts: list<string>     # Host names
]: nothing -> list<string> {
    let names = $hosts | each {|h| storage_name $h }
    glob $"($storage)/certificates/*/*"
        | where {|p| ($p | path type) == "dir" }
        | where {|p| ($names | is-empty) or ($p | path basename) in $names }
}

# Return the name Caddy uses for a host name in storage (wildcards are stored as wildcard_.<domain>)
export def storage_name [
    host: string    # Host name
]: nothing -> string {
    $host | str lowercase | str replace --regex '^\*\.' 'wildcard_.'
}
