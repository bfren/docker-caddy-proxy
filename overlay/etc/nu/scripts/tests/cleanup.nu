use std/assert
use ../bf-proxy/cleanup.nu
use ../bf-proxy/conf.nu
use ../bf-proxy/sites.nu
use helpers.nu


#======================================================================================================================
# site_name
#======================================================================================================================

export def site_name__removes_json_and_d_extensions [] {
    assert equal "example.com" (cleanup site_name "/sites/example.com.json")
    assert equal "example.com" (cleanup site_name "/sites/example.com.d")
    assert equal "example.com.conf" (cleanup site_name "/sites/example.com.conf")
}

export def site_name__matches_site_paths [] {
    # cleanup uses site_name to find the domain that a file or directory created by sites belongs to
    assert equal "example.com" (cleanup site_name (sites file_path "/sites" "example.com"))
    assert equal "example.com" (cleanup site_name (sites extras_path "/sites" "example.com"))
}


#======================================================================================================================
# keep_names
#======================================================================================================================

export def keep_names__uses_storage_names_for_wildcards [] {
    let opts = helpers opts
    let d = conf normalise {primary: "a.test", upstream: "http://a", aliases: ["*.a.test"], challenge: "dns"} $opts

    let result = cleanup keep_names {opts: $opts, domains: [$d]}

    assert equal ["a.test" "wildcard_.a.test" "proxy.test"] $result
}
