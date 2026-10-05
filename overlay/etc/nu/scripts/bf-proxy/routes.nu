use bots.nu
use conf.nu

# Response headers added to every proxied site (can be overridden per domain using 'headers' in conf.json)
export const secure_headers = {
    "Strict-Transport-Security": "max-age=63072000"
    "X-Frame-Options": "SAMEORIGIN"
    "X-Content-Type-Options": "nosniff"
    "X-XSS-Protection": "1; mode=block"
}

# Upstream status codes that cause the maintenance page to be shown
export const maintenance_codes = [502 503 504]

# Name of the maintenance page in the public directory
export const maintenance_page = "maintenance.html"

# Parse an upstream URL into a Caddy upstream dial address and whether or not it uses TLS
export def parse_upstream [upstream: string]: nothing -> record {
    let parsed = $upstream | url parse
    let tls = $parsed.scheme == "https"
    let port = if $parsed.port != "" { $parsed.port } else if $tls { "443" } else { "80" }
    {dial: $"($parsed.host):($port)", tls: $tls}
}

# Build a reverse_proxy handler for one or more upstream URLs
export def reverse_proxy [
    upstreams: list<string> # Upstream URLs - must all use the same scheme
    lb: string              # Load balancing selection policy (only used with multiple upstreams)
    public: string          # Public directory containing the maintenance page
]: nothing -> record {
    let parsed = $upstreams | each {|u| parse_upstream $u }
    let handler = {
        handler: "reverse_proxy"
        upstreams: ($parsed | each {|p| {dial: $p.dial} })
        headers: {request: {set: {"X-Real-IP": ["{http.request.remote.host}"]}}}
        handle_response: [{
            match: {status_code: $maintenance_codes}
            routes: [{handle: (maintenance_handlers $public)}]
        }]
    }

    let with_tls = if ($parsed | any {|p| $p.tls }) {
        $handler | insert transport {protocol: "http", tls: {}}
    } else { $handler }

    if ($upstreams | length) > 1 {
        $with_tls | insert load_balancing {selection_policy: {policy: $lb}}
    } else { $with_tls }
}

# Handlers that serve the maintenance page with a 503 status
export def maintenance_handlers [public: string]: nothing -> list<record> {
    [
        {handler: "rewrite", uri: $"/($maintenance_page)"}
        {handler: "headers", response: {set: {"Cache-Control": ["no-store"]}}}
        {handler: "file_server", root: $public, status_code: 503}
    ]
}

# Build a headers handler from the secure headers merged with custom headers
export def headers_handler [custom: record]: nothing -> record {
    let merged = $secure_headers | merge $custom
    let set = $merged | items {|k, v| {$k: [($v | into string)]} } | reduce --fold {} {|it, acc| $acc | merge $it }
    {handler: "headers", response: {set: $set, deferred: true}}
}

# Build a route that blocks AI bots by user agent
export def block_ai_bots_route [
    agents: list<string>    # User agents to block
]: nothing -> record {
    {
        match: [{header_regexp: {"User-Agent": {pattern: (bots pattern $agents)}}}]
        handle: [{handler: "static_response", status_code: 403}]
        terminal: true
    }
}

# Build a basic authentication handler
export def auth_handler [
    auth: any       # true (all users) or a list of user names
    users: record   # Record of {username: bcrypt hash}
]: nothing -> record {
    let names = if ($auth | describe | str starts-with "list") { $auth } else { $users | columns }
    let accounts = $names | each {|n| {username: $n, password: ($users | get $n)} }
    {handler: "authentication", providers: {http_basic: {accounts: $accounts, hash: {algorithm: "bcrypt"}, realm: "restricted"}}}
}

# Build the routes within a domain's subroute for an additional route definition from conf.json
export def custom_route [
    route: record   # Route definition from conf.json
    public: string  # Public directory containing the maintenance page
]: nothing -> record {
    let path = $route | get --optional path
    let match = if ($path | is-empty) { {} } else { {match: [{path: (conf as_list $path)}]} }

    let strip = $route | get --optional stripPrefix | default ($route | get --optional strip_prefix)
    let rewrite = if ($strip | is-empty) { [] } else { [{handler: "rewrite", strip_path_prefix: $strip}] }

    let action = if ($route | get --optional upstream) != null {
        reverse_proxy (conf as_list $route.upstream) ($route | get --optional lb | default "random") $public
    } else if ($route | get --optional redirect) != null {
        {
            handler: "static_response"
            status_code: ($route | get --optional status | default 301)
            headers: {Location: [$route.redirect]}
        }
    } else {
        {handler: "file_server", root: $route.root}
    }

    $match | merge {handle: ($rewrite | append $action), terminal: true}
}

# Build the main route for a domain - all requests for the domain's hosts are handled by a single subroute
export def domain_route [
    domain: record  # Normalised domain
    opts: record    # Options record (see conf opts)
]: nothing -> record {
    let d = $domain

    # redirect aliases to the primary domain
    let redirect = if $d.redirect_to_primary and ($d.aliases | is-not-empty) {
        [{
            match: [{not: [{host: [$d.primary]}]}]
            handle: [{
                handler: "static_response"
                status_code: 301
                headers: {Location: [$"https://($d.primary){http.request.uri}"]}
            }]
            terminal: true
        }]
    } else { [] }

    # block AI bots
    let ai_bots = $opts | get --optional ai_bots | default []
    let bots = if $opts.block_ai_bots and ($ai_bots | is-not-empty) { [(block_ai_bots_route $ai_bots)] } else { [] }

    # headers and basic auth apply to every request that gets this far
    let common = [(headers_handler $d.headers)]
        | append (if $d.auth != false { [(auth_handler $d.auth $opts.users)] } else { [] })

    # additional routes, then the default upstream
    let routes = $d.routes | each {|r| custom_route $r $opts.public }
    let default = if ($d.upstream | is-empty) { [] } else {
        [{handle: [(reverse_proxy $d.upstream $d.lb $opts.public)]}]
    }

    {
        match: [{host: (conf hosts $d)}]
        handle: [{
            handler: "subroute"
            routes: ($redirect | append $bots | append [{handle: $common}] | append $routes | append $default)
        }]
        terminal: true
    }
}

# Build the error route for a domain - shows the maintenance page when upstream servers cannot be reached
export def error_route [
    domain: record  # Normalised domain
    opts: record    # Options record (see conf opts)
]: nothing -> record {
    {
        match: [{
            host: (conf hosts $domain)
            expression: $"{http.error.status_code} in [($maintenance_codes | str join ', ')]"
        }]
        handle: (maintenance_handlers $opts.public)
        terminal: true
    }
}

# Build the route for the proxy server's own domain, which serves files from the public directory
export def proxy_domain_route [opts: record]: nothing -> record {
    {
        match: [{host: [$opts.proxy_domain]}]
        handle: [
            (headers_handler {})
            {handler: "file_server", root: $opts.public}
        ]
        terminal: true
    }
}

# Build the catch-all route that redirects requests for unknown hosts to the proxy domain
export def catch_all_route [opts: record]: nothing -> record {
    {
        handle: [{
            handler: "static_response"
            status_code: 301
            headers: {Location: [$"https://($opts.proxy_domain){http.request.uri}"]}
        }]
        terminal: true
    }
}
