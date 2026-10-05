use bf
use conf.nu
use routes.nu
use sites.nu
use tls.nu

# Generate Caddy configuration from conf.json and the per-domain configuration files, and save it
export def main [
    --domain (-d): string   # Only regenerate the configuration file for this domain (others are loaded as normal)
    --force (-f)            # Regenerate domain configuration files even if they are custom
]: nothing -> string {
    let opts = conf opts
    let domains = conf load (bf env PROXY_CONF) $opts

    # check configuration and environment
    let errors = conf validate $domains $opts | append (conf check_env $domains $opts)
    if ($errors | is-not-empty) {
        $errors | each {|e| bf write notok $e generate } | ignore
        bf write error $"($errors | length) configuration error\(s\) - see above." generate
    }

    # check requested domain exists
    if ($domain | is-not-empty) and ($domain not-in ($domains | get primary)) {
        bf write error $"Domain ($domain) is not defined in conf.json." generate
    }

    # get configuration for each domain
    bf write $"Loading configuration for ($domains | length) domain\(s\)." generate
    let sites_dir = bf env PROXY_SITES
    let configs = $domains | each {|d|
        let force_this = $force and (($domain | is-empty) or $domain == $d.primary)
        if $force_this { sites load $d $opts $sites_dir --force } else { sites load $d $opts $sites_dir }
    }

    # build and save Caddy configuration
    let caddy_conf = bf env PROXY_CADDY_CONF
    build $configs $domains $opts | to json --indent 2 | save --force $caddy_conf
    bf write debug $" .. saved to ($caddy_conf)." generate

    # validate configuration
    validate $caddy_conf
    $caddy_conf
}

# Build the full Caddy configuration
export def build [
    configs: list<record>   # Domain configurations, each with route, errors and tls keys
    domains: list<record>   # Normalised domains
    opts: record            # Options record (see conf opts)
]: nothing -> record {
    # routes: proxy domain first, then each domain, then a catch-all redirect to the proxy domain
    let https_routes = [(routes proxy_domain_route $opts)]
        | append ($configs | get route)
        | append (routes catch_all_route $opts)

    let error_routes = $configs | each {|c| $c | get --optional errors } | where $it != null

    # TLS automation: one policy per domain, then the proxy domain, then a default policy for any other names
    let policies = $configs | each {|c| $c | get --optional tls } | where $it != null
        | append (tls policy [$opts.proxy_domain] $opts.challenge $opts)
        | append (tls policy [] $opts.challenge $opts)

    # the HTTPS server - Caddy automatically adds an HTTP server to redirect HTTP to HTTPS and solve HTTP challenges
    let server = {
        listen: [":443"]
        routes: $https_routes
        errors: {routes: $error_routes}
        tls_connection_policies: (tls connection_policies $opts)
    } | merge (if $opts.access_log { {logs: {}} } else { {} })

    # when using the internal CA, do not try to install its root certificate in the container's trust store
    let pki = if $opts.internal_ca { {pki: {certificate_authorities: {local: {install_trust: false}}}} } else { {} }

    {
        admin: {listen: "localhost:2019", config: {persist: false}}
        logging: {logs: {default: {writer: {output: "stdout"}, encoder: {format: "console"}}}}
        storage: {module: "file_system", root: $opts.storage}
        apps: ($pki | merge {
            http: {
                http_port: 80
                https_port: 443
                servers: {
                    http: {
                        listen: [":80"]
                        routes: [(routes catch_all_route $opts)]
                    }
                    https: $server
                }
            }
            tls: {automation: {policies: $policies}}
        })
    }
}

# Validate a Caddy configuration file
export def validate [path: string]: nothing -> nothing {
    let ok = { bf write ok "Caddy configuration is valid." generate/validate }
    let fail = {|code, err|
        $err | print --stderr
        bf write error $"Caddy configuration ($path) is not valid." generate/validate
    }
    { ^caddy validate --config $path } | bf handle -f $fail -s $ok generate/validate
}
