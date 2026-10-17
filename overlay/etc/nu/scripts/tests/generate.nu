use std/assert
use ../bf-proxy/conf.nu
use ../bf-proxy/generate.nu *
use ../bf-proxy/sites.nu
use helpers.nu


#======================================================================================================================
# build
#======================================================================================================================

# Build Caddy configuration for a list of domain definitions
def build_for [input: list<record>, opts: record]: nothing -> record {
    let dir = mktemp --directory
    let domains = $input | each {|x| conf normalise $x $opts }
    let configs = $domains | each {|d| sites load $d $opts $dir }
    build $configs $opts
}

export def build__orders_routes_proxy_domain_first_and_catch_all_last [] {
    let result = build_for [{primary: "a.test", upstream: "http://a"}] (helpers opts)
    let routes = $result.apps.http.servers.https.routes

    assert equal 3 ($routes | length)
    assert equal [{host: ["proxy.test"]}] ($routes | first | get match)
    assert equal [{host: ["a.test"]}] ($routes | get 1 | get match)
    assert equal null ($routes | last | get --optional match)
}

export def build__adds_tls_policy_per_domain_then_proxy_domain_then_default [] {
    let result = build_for [{primary: "a.test", upstream: "http://a", aliases: ["*.a.test"], challenge: "dns"}] (helpers opts)
    let policies = $result.apps.tls.automation.policies

    assert equal 3 ($policies | length)
    assert equal ["a.test" "*.a.test"] ($policies | first | get subjects)
    assert equal ["proxy.test"] ($policies | get 1 | get subjects)
    assert equal null ($policies | last | get --optional subjects)
}

export def build__delegates_dns_challenges_to_override_zone [] {
    let opts = helpers opts | update challenge "dns" | update dns_override_zone "acme.test"
    let input = [
        {primary: "a.test", upstream: "http://a"}
        {primary: "b.test", upstream: "http://b", dnsOverrideDomain: "other.acme.test"}
    ]
    let result = build_for $input $opts
    let dns = $result.apps.tls.automation.policies | each {|p| $p.issuers.0.challenges.dns }
    let has_override = $dns | each {|x| "override_domain" in ($x | columns) }

    assert equal "a.test.acme.test" ($dns | get 0 | get override_domain)
    assert equal "other.acme.test" ($dns | get 1 | get override_domain)
    assert equal "proxy.test.acme.test" ($dns | get 2 | get override_domain)
    # the default policy has no host name to delegate
    assert equal [true true true false] $has_override
}

export def build__ignores_dns_override_zone_with_http_challenge [] {
    let opts = helpers opts | update dns_override_zone "acme.test"
    let result = build_for [] $opts
    let has_challenges = $result.apps.tls.automation.policies | each {|p| "challenges" in ($p.issuers.0 | columns) }

    assert equal [false false] $has_challenges
}

export def build__uses_storage_from_opts [] {
    let result = build_for [] (helpers opts)

    assert equal {module: "file_system", root: "/ssl/caddy"} $result.storage
}

export def build__disables_trust_install_for_internal_ca [] {
    let with = build_for [] (helpers opts | update internal_ca true)
    let without = build_for [] (helpers opts)

    assert equal false $with.apps.pki.certificate_authorities.local.install_trust
    assert equal null ($without.apps | get --optional pki)
}

export def build__adds_health_server_on_localhost [] {
    let result = build_for [] (helpers opts)
    let health = $result.apps.http.servers.health

    assert equal [$conf.health_listen] $health.listen
    assert ($conf.health_listen | str starts-with "127.0.0.1:")
    assert equal true $health.automatic_https.disable
    assert equal 200 ($health.routes.0.handle.0.status_code)
}

export def build__never_logs_health_server [] {
    let with = build_for [] (helpers opts | update access_log true)
    let without = build_for [] (helpers opts)

    # access logs are only enabled for the https server, never for health checks
    assert equal {} $with.apps.http.servers.https.logs
    assert equal null ($with.apps.http.servers.health | get --optional logs)
    assert equal null ($without.apps.http.servers.health | get --optional logs)
}

export def build__generates_valid_caddy_configuration [] {
    let input = [
        {primary: "a.test", upstream: "http://a:5000", aliases: ["www.a.test"], redirectToPrimary: true, auth: true}
        {primary: "b.test", upstream: ["https://b1" "https://b2"], lb: "round_robin", headers: {"X-Frame-Options": "DENY"}}
        {primary: "c.test", upstream: "http://c", aliases: ["*.c.test"], challenge: "dns", routes: [
            {path: "/api/*", upstream: "http://api", stripPrefix: "/api"}
            {path: "/old/*", redirect: "https://c.test/new"}
            {path: "/files/*", root: "/www/files"}
        ]}
    ]
    let opts = helpers opts | update dns_propagation_delay "30s" | update dns_resolvers ["1.1.1.1"] | update harden true
    let path = mktemp --suffix .json
    build_for $input $opts | to json | save --force $path

    let result = do { ^caddy validate --config $path } | complete

    assert equal 0 $result.exit_code $result.stderr
}
