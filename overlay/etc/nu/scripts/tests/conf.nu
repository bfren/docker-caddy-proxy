use std assert
use ../bf-proxy/conf.nu *
use helpers.nu


#======================================================================================================================
# normalise
#======================================================================================================================

export def normalise__loads_v7_domain_definition [] {
    let input = {primary: "Example.com", upstream: "http://example:5000", aliases: ["www.example.com" "ex.com"], custom: true}

    let result = normalise $input (helpers opts)

    assert equal "example.com" $result.primary
    assert equal ["www.example.com" "ex.com"] $result.aliases
    assert equal ["http://example:5000"] $result.upstream
    assert equal true $result.custom
}

export def normalise__applies_defaults_from_opts [] {
    let opts = helpers opts | update challenge "dns" | update redirect_to_primary true

    let result = normalise {primary: "a.test", upstream: "http://a"} $opts

    assert equal "dns" $result.challenge
    assert equal true $result.redirect_to_primary
    assert equal false $result.custom
    assert equal false $result.auth
    assert equal [] $result.aliases
    assert equal [] $result.routes
    assert equal true $result.clacks
    assert equal true $result.compress
}

export def normalise__clacks_can_be_disabled [] {
    let result = normalise {primary: "a.test", upstream: "http://a", clacks: false} (helpers opts)

    assert equal false $result.clacks
}

export def normalise__domain_values_override_defaults [] {
    let opts = helpers opts | update redirect_to_primary true

    let result = normalise {primary: "a.test", upstream: "http://a", challenge: "dns", redirectToPrimary: false} $opts

    assert equal "dns" $result.challenge
    assert equal false $result.redirect_to_primary
}

export def normalise__accepts_snake_case_keys [] {
    let result = normalise {primary: "a.test", upstream: "http://a", redirect_to_primary: true} (helpers opts)

    assert equal true $result.redirect_to_primary
}

export def normalise__accepts_list_of_upstreams [] {
    let result = normalise {primary: "a.test", upstream: ["http://a" "http://b"]} (helpers opts)

    assert equal ["http://a" "http://b"] $result.upstream
}


#======================================================================================================================
# validate
#======================================================================================================================

export def validate__returns_no_errors_for_valid_domains [] {
    let domains = [(helpers domain "a.test") (helpers domain "b.test")]

    let result = validate $domains (helpers opts)

    assert equal [] $result
}

export def validate__requires_primary [] {
    let domains = [(helpers domain "")]

    let result = validate $domains (helpers opts)

    assert ($result | any {|x| $x | str contains "primary must be set" })
}

export def validate__requires_upstream_unless_custom [] {
    let opts = helpers opts
    let no_upstream = normalise {primary: "a.test"} $opts
    let custom = normalise {primary: "b.test", custom: true} $opts

    let result = validate [$no_upstream $custom] $opts

    assert equal 1 ($result | length)
    assert str contains ($result | first) "a.test: upstream must be set"
}

export def validate__rejects_duplicate_hosts [] {
    let opts = helpers opts
    let a = normalise {primary: "a.test", upstream: "http://a", aliases: ["www.a.test"]} $opts
    let b = normalise {primary: "b.test", upstream: "http://b", aliases: ["www.a.test"]} $opts

    let result = validate [$a $b] $opts

    assert ($result | any {|x| $x | str contains "duplicates: www.a.test" })
}

export def validate__rejects_proxy_domain_as_site [] {
    let result = validate [(helpers domain "proxy.test")] (helpers opts)

    assert ($result | any {|x| $x | str contains "duplicates: proxy.test" })
}

export def validate__rejects_wildcard_with_http_challenge [] {
    let opts = helpers opts
    let d = normalise {primary: "a.test", upstream: "http://a", aliases: ["*.a.test"]} $opts

    let result = validate [$d] $opts

    assert ($result | any {|x| $x | str contains "require the dns challenge" })
}

export def validate__allows_wildcard_with_dns_challenge [] {
    let opts = helpers opts
    let d = normalise {primary: "a.test", upstream: "http://a", aliases: ["*.a.test"], challenge: "dns"} $opts

    let result = validate [$d] $opts

    assert equal [] $result
}

export def validate__rejects_unknown_challenge [] {
    let opts = helpers opts
    let d = normalise {primary: "a.test", upstream: "http://a", challenge: "tls"} $opts

    let result = validate [$d] $opts

    assert ($result | any {|x| $x | str contains "challenge must be one of" })
}

export def validate__rejects_unknown_auth_users [] {
    let opts = helpers opts
    let d = normalise {primary: "a.test", upstream: "http://a", auth: ["bob" "alice"]} $opts

    let result = validate [$d] $opts

    assert ($result | any {|x| $x | str contains "unknown auth users alice" })
}

export def validate__checks_routes [] {
    let opts = helpers opts
    let routes = [{path: "/a", upstream: "http://a", redirect: "https://b"} {path: "/b"} {path: "/c", upstream: "ftp://c"}]
    let d = normalise {primary: "a.test", upstream: "http://a", routes: $routes} $opts

    let result = validate [$d] $opts

    assert equal 3 ($result | length)
}


#======================================================================================================================
# check_upstream
#======================================================================================================================

export def check_upstream__accepts_http_and_https [] {
    assert equal [] (check_upstream "http://app:5000" "x")
    assert equal [] (check_upstream "https://app" "x")
    assert equal [] (check_upstream "http://app/" "x")
}

export def check_upstream__rejects_invalid_upstreams [] {
    assert equal 1 (check_upstream "ftp://app" "x" | length)
    assert equal 1 (check_upstream "http://app/path" "x" | length)
    assert equal 1 (check_upstream "not a url" "x" | length)
}


#======================================================================================================================
# check_env
#======================================================================================================================

export def check_env__requires_proxy_domain_and_email [] {
    let opts = helpers opts | update proxy_domain "" | update email ""

    let result = check_env [] $opts

    assert equal 2 ($result | length)
}

export def check_env__does_not_require_email_with_internal_ca [] {
    let opts = helpers opts | update email "" | update internal_ca true

    let result = check_env [] $opts

    assert equal [] $result
}

export def check_env__requires_desec_token_for_dns_challenge [] {
    let opts = helpers opts
    let d = normalise {primary: "a.test", upstream: "http://a", challenge: "dns"} $opts

    let without = with-env {BF_PROXY_DESEC_TOKEN: ""} { check_env [$d] $opts }
    let with = with-env {BF_PROXY_DESEC_TOKEN: "token"} { check_env [$d] $opts }

    assert ($without | any {|x| $x | str contains "BF_PROXY_DESEC_TOKEN" })
    assert equal [] $with
}


#======================================================================================================================
# load
#======================================================================================================================

export def load__returns_empty_list_when_file_does_not_exist [] {
    let result = load "/tmp/does-not-exist.json" (helpers opts)

    assert equal [] $result
}

export def load__loads_and_normalises_domains [] {
    let path = mktemp --suffix .json
    {
        "$schema": "https://schemas.bfren.dev/docker/nginx-proxy/domains.json"
        domains: [
            {primary: "example.com", upstream: "http://example:5000", aliases: ["www.example.com"], custom: true}
            {primary: "test.com", upstream: "http://test"}
        ]
    } | to json | save --force $path

    let result = load $path (helpers opts)

    assert equal ["example.com" "test.com"] ($result | get primary)
    assert equal [true false] ($result | get custom)
}
