use std/assert
use ../bf-proxy/conf.nu
use ../bf-proxy/token.nu *
use helpers.nu


#======================================================================================================================
# dns_domains
#======================================================================================================================

export def dns_domains__returns_empty_with_http_challenge [] {
    let domains = [(helpers domain "a.test")]

    assert equal [] (dns_domains $domains (helpers opts))
}

export def dns_domains__returns_domains_using_dns_challenge [] {
    let opts = helpers opts
    let domains = [
        (conf normalise {primary: "a.test", upstream: "http://a", challenge: "dns"} $opts)
        (helpers domain "b.test")
    ]

    let result = dns_domains $domains $opts | get primary

    assert equal ["a.test"] $result
}

export def dns_domains__includes_proxy_domain_with_dns_challenge [] {
    let opts = helpers opts | update challenge "dns"

    let result = dns_domains [] $opts | get primary

    assert equal ["proxy.test"] $result
}


#======================================================================================================================
# challenge_names
#======================================================================================================================

export def challenge_names__uses_acme_challenge_for_each_host [] {
    let opts = helpers opts
    let d = conf normalise {primary: "a.test", upstream: "http://a", aliases: ["www.a.test" "*.a.test"], challenge: "dns"} $opts

    let result = challenge_names [$d]

    assert equal ["_acme-challenge.a.test" "_acme-challenge.www.a.test"] $result
}

export def challenge_names__uses_override_domain [] {
    let opts = helpers opts | update dns_override_zone "acme.test"
    let d = conf normalise {primary: "a.test", upstream: "http://a", aliases: ["www.a.test"], challenge: "dns"} $opts

    let result = challenge_names [$d]

    assert equal ["a.test.acme.test"] $result
}


#======================================================================================================================
# zone_for
#======================================================================================================================

export def zone_for__returns_matching_zone [] {
    assert equal "a.test" (zone_for "_acme-challenge.www.a.test" ["a.test" "b.test"])
}

export def zone_for__returns_longest_match [] {
    assert equal "sub.a.test" (zone_for "_acme-challenge.sub.a.test" ["a.test" "sub.a.test"])
}

export def zone_for__does_not_match_partial_labels [] {
    assert equal "" (zone_for "_acme-challenge.ba.test" ["a.test"])
}

export def zone_for__returns_empty_without_zones [] {
    assert equal "" (zone_for "_acme-challenge.a.test" [])
}


#======================================================================================================================
# uncovered
#======================================================================================================================

export def uncovered__returns_names_not_in_any_zone [] {
    let names = ["_acme-challenge.a.test" "_acme-challenge.b.test"]

    assert equal ["_acme-challenge.b.test"] (uncovered $names ["a.test"])
}


#======================================================================================================================
# status_error
#======================================================================================================================

export def status_error__returns_empty_for_200 [] {
    assert equal "" (status_error 200)
}

export def status_error__reports_rejected_token [] {
    assert ((status_error 401) | str contains "rejected")
    assert ((status_error 403) | str contains "rejected")
}

export def status_error__reports_other_status [] {
    assert ((status_error 500) | str contains "500")
}
