use std/assert
use ../bf-proxy/dns.nu *
use helpers.nu


#======================================================================================================================
# all_domains
#======================================================================================================================

export def all_domains__includes_proxy_domain [] {
    let result = all_domains [(helpers domain "a.test")] (helpers opts) | get primary

    assert equal ["a.test" "proxy.test"] $result
}


#======================================================================================================================
# parents
#======================================================================================================================

export def parents__returns_host_and_each_parent [] {
    assert equal ["www.a.test" "a.test" "test"] (parents "www.a.test")
}

export def parents__removes_wildcard [] {
    assert equal ["a.test" "test"] (parents "*.a.test")
}


#======================================================================================================================
# caa_allows
#======================================================================================================================

export def caa_allows__returns_true_without_records [] {
    assert (caa_allows [] false)
}

export def caa_allows__returns_true_without_issue_records [] {
    assert (caa_allows ['0 iodef "mailto:a@a.test"'] false)
}

export def caa_allows__returns_true_when_lets_encrypt_is_allowed [] {
    assert (caa_allows ['0 issue "sectigo.com"' '0 issue "letsencrypt.org; validationmethods=dns-01"'] false)
}

export def caa_allows__returns_false_when_lets_encrypt_is_not_allowed [] {
    assert not (caa_allows ['0 issue "sectigo.com"'] false)
}

export def caa_allows__uses_issuewild_for_wildcards [] {
    let records = ['0 issue "letsencrypt.org"' '0 issuewild ";"']

    assert (caa_allows $records false)
    assert not (caa_allows $records true)
}

export def caa_allows__uses_issue_for_wildcards_without_issuewild [] {
    assert (caa_allows ['0 issue "letsencrypt.org"'] true)
}


#======================================================================================================================
# cname_error
#======================================================================================================================

export def cname_error__returns_empty_when_cname_matches [] {
    assert equal "" (cname_error "_acme-challenge.a.test" ["A.test.acme.test."] "a.test.acme.test")
}

export def cname_error__returns_empty_without_cname_or_override [] {
    assert equal "" (cname_error "_acme-challenge.a.test" [] "")
}

export def cname_error__returns_error_when_cname_is_missing [] {
    assert str contains (cname_error "_acme-challenge.a.test" [] "a.test.acme.test") "must be a CNAME"
}

export def cname_error__returns_error_when_cname_is_wrong [] {
    assert str contains (cname_error "_acme-challenge.a.test" ["b.test.acme.test."] "a.test.acme.test") "not a.test.acme.test"
}

export def cname_error__returns_error_when_cname_is_unexpected [] {
    assert str contains (cname_error "_acme-challenge.a.test" ["a.test.acme.test."] "") "set dnsOverrideDomain"
}
