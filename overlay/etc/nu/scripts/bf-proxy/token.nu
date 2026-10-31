use bf
use conf.nu

# API used to test each DNS provider's token - a successful response lists the zones the token can manage
export const zones_api = {
    hetzner: "https://api.hetzner.cloud/v1/zones?per_page=50"
}

# Verify the DNS provider token by listing the zones it can manage, and check every DNS challenge record is in one of them
export def main []: nothing -> nothing {
    let config = conf read
    let opts = $config.opts
    let names = challenge_names (dns_domains $config.domains $opts)

    if ($names | is-empty) {
        bf write ok "Not set up - no domains use the dns challenge, so no token is needed." token
        return
    }
    if $opts.internal_ca {
        bf write ok "Not set up - Caddy's internal CA is in use, so no token is needed." token
        return
    }

    let var = conf token_var $opts
    let token = bf env --safe $var
    if $token == "" { bf write error $"BF_($var) is not set." token }

    let url = $zones_api | get $opts.dns_provider
    bf write $"Listing ($opts.dns_provider) zones using BF_($var)." token
    let response = try {
        http get --full --allow-errors --headers {Authorization: $"Bearer ($token)"} $url
    } catch {|e|
        bf write error $"Unable to reach ($url): ($e.msg)" token
    }

    let failed = status_error $response.status
    if $failed != "" { bf write error $failed token }

    let body = $response.body | if ($in | describe) == "string" { $in | from json } else { $in }
    let zones = $body.zones | each {|z| $z.name }
    if ($zones | is-empty) {
        bf write error "The token is valid, but its project has no zones - create it in the project that holds your DNS zones." token
    }
    bf write ok $"The token is valid - zones: ($zones | str join ', ')" token
    if ($body | get --optional meta.pagination.next_page) != null {
        bf write warn "There are more zones than were listed, so some records may be reported as missing when they are not." token
    }

    let missing = uncovered $names $zones
    if ($missing | is-not-empty) {
        $missing | each {|n| bf write notok $" .. ($n) is not in any of these zones" token } | ignore
        bf write error "Certificates for these host names cannot be issued with this token." token
    }
    bf write ok "Every DNS challenge record is in one of these zones." token
    bf write "Write permission cannot be checked without changing records - if issuing fails, check the token is read / write." token
}

# Return the domains using the dns challenge, including the proxy domain when it does
export def dns_domains [
    domains: list<record>   # Normalised domains
    opts: record            # Options record (see conf opts)
]: nothing -> list<record> {
    let proxy = if $opts.proxy_domain == "" { [] } else { [(conf normalise {primary: $opts.proxy_domain} $opts)] }
    $domains | append $proxy | where challenge == "dns"
}

# Return the names of the TXT records created for DNS challenges - the override domain if set, otherwise
# _acme-challenge.<host> for each host name (wildcards use the name without *.)
export def challenge_names [
    domains: list<record>   # Normalised domains using the dns challenge
]: nothing -> list<string> {
    $domains
        | each {|d|
            if $d.dns_override != "" { [$d.dns_override] } else {
                conf hosts $d | each {|h| $"_acme-challenge.($h | str replace --regex '^\*\.' '')" }
            }
        }
        | flatten
        | uniq
}

# Return the zone containing a record name - the longest match, or "" if there is none
export def zone_for [
    name: string        # Record name, e.g. _acme-challenge.www.example.com
    zones: list<string> # Zone names, e.g. example.com
]: nothing -> string {
    $zones
        | where {|z| $name == $z or ($name | str ends-with $".($z)") }
        | each {|z| {name: $z, length: ($z | str length)} }
        | sort-by --reverse length
        | get --optional 0.name
        | default ""
}

# Return the record names that are not in any of the zones
export def uncovered [
    names: list<string> # Record names
    zones: list<string> # Zone names
]: nothing -> list<string> {
    $names | where {|n| (zone_for $n $zones) == "" }
}

# Return an error message for an unsuccessful HTTP status, or "" if it succeeded
export def status_error [
    status: int # HTTP status code
]: nothing -> string {
    match $status {
        200 => ""
        401 | 403 => $"The token was rejected \(HTTP ($status)\) - it is wrong, revoked, or not a Cloud API token."
        _ => $"Unexpected response from the DNS provider \(HTTP ($status)\)."
    }
}
