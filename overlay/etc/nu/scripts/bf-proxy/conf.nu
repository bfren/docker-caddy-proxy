use bf
use bots.nu

# Valid ACME challenge types
export const challenges = ["http" "dns"]

# Valid load balancing selection policies
export const lb_policies = ["random" "round_robin" "least_conn" "first" "ip_hash" "uri_hash" "client_ip_hash"]

# Build the options record used to generate configuration, using the current environment
export def opts []: nothing -> record {
    {
        proxy_domain: (bf env PROXY_DOMAIN --safe)
        email: (bf env PROXY_LETS_ENCRYPT_EMAIL --safe)
        live: (bf env check PROXY_LETS_ENCRYPT_LIVE)
        internal_ca: (bf env check PROXY_USE_INTERNAL_CA)
        challenge: (bf env PROXY_ACME_CHALLENGE "http")
        dns_propagation_delay: (bf env PROXY_DNS_PROPAGATION_DELAY --safe)
        dns_propagation_timeout: (bf env PROXY_DNS_PROPAGATION_TIMEOUT --safe)
        dns_resolvers: (bf env PROXY_DNS_RESOLVERS --safe | split row " " | where $it != "")
        harden: (bf env check PROXY_HARDEN)
        redirect_to_primary: (bf env check PROXY_SSL_REDIRECT_TO_CANONICAL)
        block_ai_bots: (bf env check PROXY_BLOCK_AI_BOTS)
        ai_bots: (bots load (bf env PROXY_AI_BOTS --safe))
        access_log: (bf env check PROXY_ACCESS_LOG)
        public: (bf env PROXY_PUBLIC --safe)
        storage: (bf env PROXY_STORAGE --safe)
        users: (load_users (bf env PROXY_USERS --safe))
    }
}

# Load the conf.json file and return the list of normalised domains
export def load [
    path: string    # Absolute path to conf.json
    opts: record    # Options record (see opts)
]: nothing -> list<record> {
    # without conf.json only the proxy domain will be served
    if ($path | bf fs is_not_file) {
        bf write warn $"($path) does not exist - see proxy-conf-sample.json." conf/load
        return []
    }

    let json = try { open --raw $path | from json } catch {
        bf write error $"($path) is not valid JSON." conf/load
    }

    $json | get --optional domains | default [] | each {|x| normalise $x $opts }
}

# Normalise a domain definition from conf.json, applying defaults from $opts -
# keys may be written in camelCase (preferred) or snake_case
export def normalise [
    domain: record  # Domain definition from conf.json
    opts: record    # Options record (see opts)
]: nothing -> record {
    let d = $domain
    let get_key = {|camel: string, snake: string| $d | get --optional $camel | default ($d | get --optional $snake) }

    {
        primary: ($d | get --optional primary | default "" | str trim | str downcase)
        aliases: ($d | get --optional aliases | default [] | each {|x| $x | str trim | str downcase } | where $it != "")
        upstream: (as_list ($d | get --optional upstream))
        lb: ($d | get --optional lb | default "random")
        challenge: ($d | get --optional challenge | default $opts.challenge)
        redirect_to_primary: (do $get_key redirectToPrimary redirect_to_primary | default $opts.redirect_to_primary)
        auth: ($d | get --optional auth | default false)
        headers: ($d | get --optional headers | default {})
        routes: ($d | get --optional routes | default [])
        custom: ($d | get --optional custom | default false)
    }
}

# Convert a nullable string or list into a list
export def as_list [value: any]: nothing -> list<string> {
    match ($value | describe | str replace --regex '<.*' '') {
        "nothing" => []
        "string" => (if ($value | str trim) == "" { [] } else { [$value] })
        "list" => $value
        _ => [($value | into string)]
    }
}

# Return all host names (primary and aliases) for a normalised domain
export def hosts [domain: record]: nothing -> list<string> { [$domain.primary] | append $domain.aliases }

# Validate a list of normalised domains, returning a list of error messages (empty if valid)
export def validate [
    domains: list<record>   # Normalised domains
    opts: record            # Options record (see opts)
]: nothing -> list<string> {
    # per-domain checks
    let per_domain = $domains | enumerate | each {|x|
        let d = $x.item
        let name = if $d.primary == "" { $"domains[($x.index)]" } else { $d.primary }
        mut errors = []

        if $d.primary == "" { $errors = $errors | append $"($name): primary must be set." }
        if ($d.primary | str starts-with "*") { $errors = $errors | append $"($name): primary cannot be a wildcard." }
        if $d.challenge not-in $challenges { $errors = $errors | append $"($name): challenge must be one of ($challenges | str join ', ')." }
        if $d.lb not-in $lb_policies { $errors = $errors | append $"($name): lb must be one of ($lb_policies | str join ', ')." }

        # wildcard certificates can only be issued using the DNS challenge
        let wildcards = hosts $d | where ($it | str starts-with "*")
        if ($wildcards | is-not-empty) and $d.challenge != "dns" {
            $errors = $errors | append $"($name): wildcard aliases \(($wildcards | str join ', ')\) require the dns challenge."
        }

        # there must be a default upstream unless the domain is custom (when the user controls everything)
        if ($d.upstream | is-empty) and (not $d.custom) { $errors = $errors | append $"($name): upstream must be set." }
        $errors = $errors | append ($d.upstream | each {|u| check_upstream $u $name } | flatten)

        # check each additional route
        $errors = $errors | append ($d.routes | enumerate | each {|r| check_route $r.item $"($name) routes[($r.index)]" } | flatten)

        # basic auth users must exist
        if ($d.auth | describe | str starts-with "list") {
            let missing = $d.auth | where $it not-in ($opts.users | columns)
            if ($missing | is-not-empty) { $errors = $errors | append $"($name): unknown auth users ($missing | str join ', ')." }
        }

        $errors
    } | flatten

    # host names must be unique across all domains (including the proxy domain)
    let all_hosts = $domains | each {|d| hosts $d } | flatten | append $opts.proxy_domain | where $it != ""
    let duplicates = $all_hosts | uniq --repeated
    let dup_errors = if ($duplicates | is-empty) { [] } else { [$"Host names must be unique - duplicates: ($duplicates | str join ', ')."] }

    $per_domain | append $dup_errors
}

# Validate an upstream URL, returning a list of error messages
export def check_upstream [
    upstream: string    # Upstream URL, e.g. http://app:5000
    name: string        # Name to use in error messages
]: nothing -> list<string> {
    let invalid = [$"($name): upstream '($upstream)' is not a valid URL."]
    let parsed = try { $upstream | url parse } catch { return $invalid }
    if $parsed.scheme == "" or $parsed.host == "" { return $invalid }

    mut errors = []
    if $parsed.scheme not-in ["http" "https"] { $errors = $errors | append $"($name): upstream '($upstream)' must use http or https." }
    if $parsed.path not-in ["" "/"] { $errors = $errors | append $"($name): upstream '($upstream)' cannot include a path - use a route with stripPrefix instead." }
    $errors
}

# Validate an additional route definition, returning a list of error messages
export def check_route [
    route: record   # Route definition
    name: string    # Name to use in error messages
]: nothing -> list<string> {
    let actions = ["upstream" "redirect" "root"] | where {|k| ($route | get --optional $k) != null }
    if ($actions | length) != 1 { return [$"($name): must have exactly one of upstream, redirect or root."] }
    if "upstream" in $actions {
        as_list $route.upstream | each {|u| check_upstream $u $name } | flatten
    } else { [] }
}

# Check environment variables required to generate configuration, returning a list of error messages
export def check_env [
    domains: list<record>   # Normalised domains
    opts: record            # Options record (see opts)
]: nothing -> list<string> {
    mut errors = []
    if $opts.proxy_domain == "" { $errors = $errors | append "BF_PROXY_DOMAIN must be set." }
    if $opts.email == "" and (not $opts.internal_ca) { $errors = $errors | append "BF_PROXY_LETS_ENCRYPT_EMAIL must be set." }
    if $opts.challenge not-in $challenges { $errors = $errors | append $"BF_PROXY_ACME_CHALLENGE must be one of ($challenges | str join ', ')." }

    let uses_dns = ($opts.challenge == "dns") or ($domains | any {|d| $d.challenge == "dns" })
    if $uses_dns and (bf env PROXY_DESEC_TOKEN --safe) == "" and (not $opts.internal_ca) {
        $errors = $errors | append "BF_PROXY_DESEC_TOKEN must be set to use the dns challenge."
    }
    $errors
}

# Load basic auth users from a JSON file of {username: bcrypt hash}
export def load_users [path: string]: nothing -> record {
    if $path == "" or ($path | bf fs is_not_file) { return {} }
    try { open --raw $path | from json } catch { bf write error $"($path) is not valid JSON." conf/load_users }
}
