use std/assert
use ../bf-proxy/cleanup.nu
use ../bf-proxy/sites.nu


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
