use std/assert
use ../bf-proxy/renew.nu *


#======================================================================================================================
# check_args
#======================================================================================================================

export def check_args__requires_all_or_domain [] {
    assert equal false (check_args false "")
}

export def check_args__accepts_all [] {
    assert equal true (check_args true "")
}

export def check_args__accepts_domain [] {
    assert equal true (check_args false "a.test")
}

export def check_args__rejects_all_and_domain [] {
    assert equal false (check_args true "a.test")
}


#======================================================================================================================
# cert_dirs
#======================================================================================================================

# Create a Caddy storage directory containing certificate directories for the given host names
def storage [...names: string]: nothing -> string {
    let dir = mktemp --directory
    $names | each {|n| mkdir $"($dir)/certificates/acme-v02.api.letsencrypt.org-directory/($n)" } | ignore
    $dir
}

export def cert_dirs__returns_all_when_no_hosts [] {
    let dir = storage "a.test" "b.test"

    let result = cert_dirs $dir [] | each { path basename } | sort

    assert equal ["a.test" "b.test"] $result
}

export def cert_dirs__returns_only_matching_hosts [] {
    let dir = storage "a.test" "www.a.test" "b.test"

    let result = cert_dirs $dir ["a.test" "www.a.test"] | each { path basename } | sort

    assert equal ["a.test" "www.a.test"] $result
}

export def cert_dirs__matches_wildcards [] {
    let dir = storage "wildcard_.a.test" "b.test"

    let result = cert_dirs $dir ["*.a.test"] | each { path basename }

    assert equal ["wildcard_.a.test"] $result
}

export def cert_dirs__returns_empty_when_storage_does_not_exist [] {
    assert equal [] (cert_dirs "/tmp/does-not-exist" [])
}


#======================================================================================================================
# storage_name
#======================================================================================================================

export def storage_name__replaces_wildcard_and_lowercases [] {
    assert equal "wildcard_.a.test" (storage_name "*.A.test")
    assert equal "www.a.test" (storage_name "www.a.test")
}
