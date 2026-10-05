use std assert
use ../bf-proxy tls *
use helpers.nu


#======================================================================================================================
# issuer
#======================================================================================================================

export def issuer__uses_staging_by_default [] {
    let result = issuer "http" (helpers opts)

    assert equal "acme" $result.module
    assert equal $lets_encrypt_staging $result.ca
    assert equal "test@proxy.test" $result.email
    assert equal null ($result | get --optional challenges)
}

export def issuer__uses_live_when_enabled [] {
    let result = issuer "http" (helpers opts | update live true)

    assert equal $lets_encrypt_live $result.ca
}

export def issuer__uses_internal_ca_when_enabled [] {
    let result = issuer "dns" (helpers opts | update internal_ca true)

    assert equal {module: "internal"} $result
}

export def issuer__dns_uses_desec_and_disables_other_challenges [] {
    let result = issuer "dns" (helpers opts)

    assert equal {name: "desec", token: "{env.BF_PROXY_DESEC_TOKEN}"} $result.challenges.dns.provider
    assert equal true $result.challenges.http.disabled
    assert equal true ($result.challenges | get tls-alpn | get disabled)
}


#======================================================================================================================
# dns_challenge
#======================================================================================================================

export def dns_challenge__omits_optional_values_when_not_set [] {
    let result = dns_challenge (helpers opts)

    assert equal ["provider"] ($result | columns)
}

export def dns_challenge__includes_optional_values_when_set [] {
    let opts = helpers opts
        | update dns_propagation_delay "60s"
        | update dns_propagation_timeout "5m"
        | update dns_resolvers ["1.1.1.1" "9.9.9.9"]

    let result = dns_challenge $opts

    assert equal "60s" $result.propagation_delay
    assert equal "5m" $result.propagation_timeout
    assert equal ["1.1.1.1" "9.9.9.9"] $result.resolvers
}


#======================================================================================================================
# policy / connection_policies
#======================================================================================================================

export def policy__includes_subjects [] {
    let result = policy ["a.test" "*.a.test"] "dns" (helpers opts)

    assert equal ["a.test" "*.a.test"] $result.subjects
    assert equal 1 ($result.issuers | length)
}

export def policy__without_subjects_is_default_policy [] {
    let result = policy [] "http" (helpers opts)

    assert equal ["issuers"] ($result | columns)
}

export def connection_policies__uses_proxy_domain_as_fallback [] {
    let result = connection_policies (helpers opts)

    assert equal [{fallback_sni: "proxy.test"}] $result
}

export def connection_policies__harden_requires_tls_1_3 [] {
    let result = connection_policies (helpers opts | update harden true)

    assert equal "tls1.3" $result.0.protocol_min
}
