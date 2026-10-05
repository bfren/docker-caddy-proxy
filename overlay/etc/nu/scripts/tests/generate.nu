use std assert
use ../bf-proxy conf
use ../bf-proxy generate *
use ../bf-proxy sites
use helpers.nu


#======================================================================================================================
# build
#======================================================================================================================

# Build Caddy configuration for a list of domain definitions
def build_for [input: list<record>, opts: record]: nothing -> record {
    let dir = mktemp --directory
    let domains = $input | each {|x| conf normalise $x $opts }
    let configs = $domains | each {|d| sites load $d $opts $dir }
    build $configs $domains $opts
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
