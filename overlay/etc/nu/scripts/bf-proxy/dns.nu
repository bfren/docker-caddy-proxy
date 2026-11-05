use bf
use conf.nu

# DNS-over-HTTPS API used to look up records - public DNS, as Let's Encrypt sees it, not the container's resolver
export const doh_api = "https://dns.google/resolve"

# CA that CAA records must allow when using Let's Encrypt
export const lets_encrypt_caa = "letsencrypt.org"

# DNS record type codes used in DNS-over-HTTPS answers
const types = {A: 1, AAAA: 28, CNAME: 5, CAA: 257}

# Check the public DNS records each host name needs before Let's Encrypt can issue its certificate
export def main []: nothing -> nothing {
    let config = conf read
    if ($config.errors | is-not-empty) {
        $config.errors | each {|e| bf write notok $e dns } | ignore
        bf write error $"($config.errors | length) configuration error\(s\) - see above." dns
    }

    let opts = $config.opts
    if $opts.internal_ca {
        bf write ok "Not needed - Caddy's internal CA is in use, so no public DNS records are needed." dns
        return
    }

    bf write $"Checking public DNS records using ($doh_api)." dns
    let proxy_addresses = addresses $opts.proxy_domain
    let results = all_domains $config.domains $opts
        | each {|d| conf hosts $d | each {|h| check_host $h $d $proxy_addresses } | flatten }
        | flatten

    $results | each {|r|
        match $r.level {
            "ok" => (bf write ok $r.message dns)
            "warn" => (bf write warn $r.message dns)
            _ => (bf write notok $r.message dns)
        }
    } | ignore

    let failed = $results | where level == "notok" | length
    if $failed > 0 { bf write error $"($failed) DNS problem\(s\) - certificates for these host names cannot be issued." dns }
    bf write ok "Every host name has the DNS records it needs." dns
}

# Return all domains, including the proxy domain
export def all_domains [
    domains: list<record>   # Normalised domains
    opts: record            # Options record (see conf opts)
]: nothing -> list<record> {
    let proxy = if $opts.proxy_domain == "" { [] } else { [(conf normalise {primary: $opts.proxy_domain} $opts)] }
    $domains | append $proxy
}

# Check the DNS records for one host name, returning a list of {level, message}
def check_host [
    host: string                    # Host name
    domain: record                  # Normalised domain the host belongs to
    proxy_addresses: list<string>   # Addresses of the proxy domain, i.e. this server
]: nothing -> list<record> {
    let caa = if (caa_allows (caa_records $host) ($host | str starts-with "*.")) { [] } else {
        [{level: "notok", message: $"($host): CAA records do not allow ($lets_encrypt_caa) to issue certificates"}]
    }

    let challenge = if $domain.challenge == "dns" {
        let name = $"_acme-challenge.($host | str replace --regex '^\*\.' '')"
        let e = cname_error $name (lookup $name CNAME) $domain.dns_override
        if $e == "" { [] } else { [{level: "notok", message: $e}] }
    } else {
        let a = addresses $host
        # Let's Encrypt may use any of the addresses (it prefers IPv6), so every one must reach this server
        let other = $a | where $it not-in $proxy_addresses
        if ($a | is-empty) {
            [{level: "notok", message: $"($host) has no A or AAAA records - the http challenge needs them to point to this server"}]
        } else if ($proxy_addresses | is-not-empty) and ($other | is-not-empty) {
            [{level: "warn", message: $"($host) points to ($other | str join ', '), which BF_PROXY_DOMAIN does not - ignore this if it still reaches this server"}]
        } else { [] }
    }

    let issues = $caa | append $challenge
    if ($issues | is-empty) { [{level: "ok", message: $host}] } else { $issues }
}

# Return the A and AAAA records of a host name
def addresses [host: string]: nothing -> list<string> {
    if $host == "" { return [] }
    lookup $host A | append (lookup $host AAAA)
}

# Return the CAA records that apply to a host name - the closest ones found walking up the tree (RFC 8659)
def caa_records [host: string]: nothing -> list<string> {
    parents $host
        | each {|n| lookup $n CAA }
        | where ($it | is-not-empty)
        | get --optional 0
        | default []
}

# Look up records of one type using DNS-over-HTTPS, returning their values (empty if there are none)
export def lookup [
    name: string    # Record name
    type: string    # Record type (A, AAAA, CNAME or CAA)
]: nothing -> list<string> {
    let url = $"($doh_api)?name=($name | url encode)&type=($type)"
    let response = try { http get $url } catch {|e|
        bf write error $"Unable to look up ($type) records for ($name): ($e.msg)" dns
    }
    $response
        | if ($in | describe) == "string" { $in | from json } else { $in }
        | get --optional Answer
        | default []
        | where type == ($types | get $type)
        | get data
}

# Return a host name and each of its parents, e.g. [www.example.com example.com com] (wildcards use the name without *.)
export def parents [host: string]: nothing -> list<string> {
    let labels = $host | str replace --regex '^\*\.' '' | split row "."
    0..<($labels | length) | each {|i| $labels | skip $i | str join "." }
}

# Return whether CAA records allow Let's Encrypt to issue a certificate (no issue records allows every CA)
export def caa_allows [
    records: list<string>   # CAA records, e.g. 0 issue "letsencrypt.org"
    wildcard: bool          # Whether the certificate is for a wildcard - issuewild records take precedence
]: nothing -> bool {
    let parsed = $records
        | each {|r| $r | parse --regex '^\d+\s+(?<tag>\S+)\s+"?(?<value>[^"]*)"?$' }
        | flatten
        | each {|x| $x | update tag ($x.tag | str lowercase) }
    let wild = $parsed | where tag == "issuewild"
    let issue = if $wildcard and ($wild | is-not-empty) { $wild } else { $parsed | where tag == "issue" }
    # values may have parameters after the CA, e.g. letsencrypt.org; validationmethods=dns-01
    ($issue | is-empty) or ($issue | any {|x| ($x.value | split row ";" | first | str trim | str lowercase) == $lets_encrypt_caa })
}

# Return an error message if a host's _acme-challenge CNAME is not what the dns challenge needs, or "" if it is
export def cname_error [
    name: string            # Record name, e.g. _acme-challenge.www.example.com
    cname: list<string>     # CNAME records found for the name
    expected: string        # The domain's override domain, or "" if it should not be a CNAME
]: nothing -> string {
    let actual = $cname | get --optional 0 | default "" | str trim --right --char "." | str lowercase
    if $actual == $expected {
        ""
    } else if $expected == "" {
        $"($name) is a CNAME to ($actual) - set dnsOverrideDomain to ($actual) so Caddy creates the record there"
    } else if $actual == "" {
        $"($name) must be a CNAME to ($expected)."
    } else {
        $"($name) is a CNAME to ($actual), not ($expected)."
    }
}
