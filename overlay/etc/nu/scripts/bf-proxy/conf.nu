use bf
use bots.nu

# Schema
export const schema = "https://raw.githubusercontent.com/bfren/docker-caddy-proxy/main/proxy-conf-schema.json"

# Valid ACME challenge types
export const challenges = ["http" "dns"]

# Valid retry durations (empty disables retries)
export const duration_pattern = '^(\d+(ms|s|m))?$'

# Valid load balancing selection policies
export const lb_policies = ["random" "round_robin" "least_conn" "first" "ip_hash" "uri_hash" "client_ip_hash"]

# Build the options record used to generate configuration, using the current environment
export def opts []: nothing -> record {
    {
        proxy_domain: (bf env --safe PROXY_DOMAIN)
        email: (bf env --safe PROXY_LETS_ENCRYPT_EMAIL)
        live: (bf env check PROXY_LETS_ENCRYPT_LIVE)
        internal_ca: (bf env check PROXY_USE_INTERNAL_CA)
        challenge: (bf env PROXY_ACME_CHALLENGE "http")
        retry: (bf env --safe PROXY_UPSTREAM_RETRY)
        dns_propagation_delay: (bf env --safe PROXY_DNS_PROPAGATION_DELAY)
        dns_propagation_timeout: (bf env --safe PROXY_DNS_PROPAGATION_TIMEOUT)
        dns_resolvers: (bf env --safe PROXY_DNS_RESOLVERS | split row " " | where $it != "")
        harden: (bf env check PROXY_HARDEN)
        redirect_to_primary: (bf env check PROXY_SSL_REDIRECT_TO_CANONICAL)
        block_ai_bots: (bf env check PROXY_BLOCK_AI_BOTS)
        ai_bots: (bots load (bf env --safe PROXY_AI_BOTS))
        access_log: (bf env check PROXY_ACCESS_LOG)
        public: (bf env --safe PROXY_PUBLIC)
        storage: (bf env --safe PROXY_STORAGE)
        users: (load_users (bf env --safe PROXY_USERS))
    }
}

# Read options from the environment and domains from conf.json, and check both for errors
export def read []: nothing -> record {
    let opts = opts
    let domains = load (bf env PROXY_CONF) $opts
    let errors = validate $domains $opts | append (check_env $domains $opts)
    {opts: $opts, domains: $domains, errors: $errors}
}

# Open and parse a JSON file, writing an error if it is not valid JSON
export def open_json [
    path: string    # Path to the JSON file
    script: string  # The name of the calling script (used in the error message)
]: nothing -> any {
    try {
        open --raw $path | from json
    } catch {
        bf write error $"($path) is not valid JSON." $script
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

    open_json $path conf/load
        | get --optional domains
        | default []
        | each {|x| normalise $x $opts }
}

# Normalise a domain definition from conf.json, applying defaults from $opts
export def normalise [
    domain: record  # Domain definition from conf.json
    opts: record    # Options record (see opts)
]: nothing -> record {
    let d = $domain
    {
        primary: ($d
            | get --optional primary
            | default ""
            | str trim
            | str downcase
        )
        aliases: ($d
            | get --optional aliases
            | default []
            | each {|x| $x | str trim | str downcase }
            | where $it != ""
        )
        upstream: ($d
            | get --optional upstream
            | as_list
        )
        lb: ($d
            | get --optional lb
            | default "random"
        )
        retry: ($d
            | get --optional retry
            | default $opts.retry
            | into string
        )
        challenge: ($d
            | get --optional challenge
            | default $opts.challenge
        )
        redirect_to_primary: ($d
            | get --optional redirectToPrimary
            | default $opts.redirect_to_primary
        )
        auth: ($d
            | get --optional auth
            | default false
        )
        headers: ($d
            | get --optional headers
            | default {}
        )
        routes: ($d
            | get --optional routes
            | default []
        )
        clacks: ($d
            | get --optional clacks
            | default true
        )
        compress: ($d
            | get --optional compress
            | default true
        )
        custom: ($d
            | get --optional custom
            | default false
        )
    }
}

# Convert a value that may be missing, a string or a list into a list of non-empty strings
export def as_list []: any -> list<string> {
    [$in]
        | flatten
        | where {|x| $x != null }
        | each {|x| $x | into string | str trim }
        | where {|x| $x != "" }
}

# Return all host names (primary and aliases) for a normalised domain
export def hosts [domain: record]: nothing -> list<string> {
    [$domain.primary] | append $domain.aliases
}

# Return the messages of rules that have failed - each rule is a list of [failed: bool, message: string]
export def failures [
    --prefix: string    # Optional prefix for each message, e.g. the domain name
    rules: list         # Rules to check
]: nothing -> list<string> {
    $rules
        | where {|r| $r.0 }
        | each {|r| if ($prefix | is-empty) { $"($r.1)." } else { $"($prefix): ($r.1)." } }
}

# Validate a list of normalised domains, returning a list of error messages (empty if valid)
export def validate [
    domains: list<record>   # Normalised domains
    opts: record            # Options record (see opts)
]: nothing -> list<string> {
    let per_domain = $domains
        | enumerate
        | each {|x| validate_domain $x.item $x.index $opts }
        | flatten

    # host names must be unique across all domains (including the proxy domain)
    let duplicates = $domains
        | each {|d| hosts $d }
        | flatten
        | append $opts.proxy_domain
        | where $it != ""
        | uniq --repeated

    $per_domain | append (failures [
        [($duplicates | is-not-empty)   $"Host names must be unique - duplicates: ($duplicates | str join ', ')"]
    ])
}

# Validate a normalised domain, returning a list of error messages (empty if valid)
export def validate_domain [
    d: record       # Normalised domain
    index: int      # Position of the domain in conf.json (used in messages when primary is not set)
    opts: record    # Options record (see opts)
]: nothing -> list<string> {
    let name = if $d.primary == "" { $"domains[($index)]" } else { $d.primary }
    let wildcards = hosts $d | where ($it | str starts-with "*")
    let unknown_users = if ($d.auth | describe | str starts-with "list") {
        $d.auth | where $it not-in ($opts.users | columns)
    } else {
        []
    }

    let domain_errors = failures --prefix $name [
        [
            ($d.primary == "")
            "primary must be set"
        ]
        [
            ($d.primary | str starts-with "*")
            "primary cannot be a wildcard"
        ]
        [
            ($d.challenge not-in $challenges)
            $"challenge must be one of ($challenges | str join ', ')"
        ]
        [
            ($d.lb not-in $lb_policies)
            $"lb must be one of ($lb_policies | str join ', ')"
        ]
        [
            (not ($d.retry =~ $duration_pattern))
            $"retry '($d.retry)' must be a duration, e.g. 5s, 500ms or 1m"
        ]
        # wildcard certificates can only be issued using the DNS challenge
        [
            (($wildcards | is-not-empty) and $d.challenge != "dns")
            $"wildcard aliases \(($wildcards | str join ', ')\) require the dns challenge"
        ]
        # there must be a default upstream unless the domain is custom (when the user controls everything)
        [
            (($d.upstream | is-empty) and (not $d.custom))
            "upstream must be set"
        ]
        [
            ($unknown_users | is-not-empty)
            $"unknown auth users ($unknown_users | str join ', ')"
        ]
    ]

    let upstream_errors = $d.upstream
        | each {|u| check_upstream $u $name }
        | flatten
    let route_errors = $d.routes
        | enumerate
        | each {|r| check_route $r.item $"($name) routes[($r.index)]" }
        | flatten

    [...$domain_errors ...$upstream_errors ...$route_errors]
}

# Validate an upstream URL, returning a list of error messages
export def check_upstream [
    upstream: string    # Upstream URL, e.g. http://app:5000
    name: string        # Name to use in error messages
]: nothing -> list<string> {
    let parsed = try {
        $upstream | url parse
    } catch {
        {scheme: "", host: "", path: ""}
    }

    if $parsed.scheme == "" or $parsed.host == "" {
        return (failures --prefix $name [[true $"upstream '($upstream)' is not a valid URL"]])
    }

    failures --prefix $name [
        [
            ($parsed.scheme not-in ["http" "https"])
            $"upstream '($upstream)' must use http or https"
        ]
        [
            ($parsed.path not-in ["" "/"])
            $"upstream '($upstream)' cannot include a path - use a route with stripPrefix instead"
        ]
    ]
}

# Validate an additional route definition, returning a list of error messages
export def check_route [
    route: record   # Route definition
    name: string    # Name to use in error messages
]: nothing -> list<string> {
    let actions = ["upstream" "redirect" "root"] | where {|k| ($route | get --optional $k) != null }
    if ($actions | length) != 1 {
        return (failures --prefix $name [[true "must have exactly one of upstream, redirect or root"]])
    }

    $route
        | get --optional upstream
        | as_list
        | each {|u| check_upstream $u $name }
        | flatten
}

# Check environment variables required to generate configuration, returning a list of error messages
export def check_env [
    domains: list<record>   # Normalised domains
    opts: record            # Options record (see opts)
]: nothing -> list<string> {
    let uses_dns = ($opts.challenge == "dns") or ($domains | any {|d| $d.challenge == "dns" })
    let no_token = (bf env --safe PROXY_DESEC_TOKEN) == ""

    failures [
        [($opts.proxy_domain == "")                             "BF_PROXY_DOMAIN must be set"]
        [($opts.email == "" and (not $opts.internal_ca))        "BF_PROXY_LETS_ENCRYPT_EMAIL must be set"]
        [($opts.challenge not-in $challenges)                   $"BF_PROXY_ACME_CHALLENGE must be one of ($challenges | str join ', ')"]
        [($uses_dns and $no_token and (not $opts.internal_ca))  "BF_PROXY_DESEC_TOKEN must be set to use the dns challenge"]
    ]
}

# Load basic auth users from a JSON file of {username: bcrypt hash}
export def load_users [path: string]: nothing -> record {
    if $path == "" or ($path | bf fs is_not_file) { return {} }
    open_json $path conf/load_users
}
