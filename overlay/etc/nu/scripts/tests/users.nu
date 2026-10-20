use std/assert
use ../bf-proxy/conf.nu
use ../bf-proxy/users.nu


#======================================================================================================================
# helpers
#======================================================================================================================

# Run a closure with a stub caddy first on PATH - 'caddy hash-password' outputs 'hash-<password>'
def with_caddy [action: closure]: nothing -> any {
    let dir = mktemp --directory
    "#!/bin/sh\necho \"hash-$3\"\n" | save $"($dir)/caddy"
    ^chmod +x $"($dir)/caddy"
    let path = [$dir] | append ($env.PATH | [$in] | flatten | str join (char esep) | split row (char esep))
    with-env {PATH: $path} { do $action }
}


#======================================================================================================================
# add
#======================================================================================================================

export def add__creates_users_file_with_hashed_password [] {
    let file = $"(mktemp --directory)/users.json"
    with_caddy { with-env {BF_PROXY_USERS: $file} { users add fred secret } }

    assert equal {fred: "hash-secret"} (open --raw $file | from json)
}

export def add__keeps_other_users_and_replaces_existing [] {
    let file = $"(mktemp --directory)/users.json"
    {fred: "old", jones: "hash-jones"} | to json | save $file

    with_caddy { with-env {BF_PROXY_USERS: $file} { users add fred new } }

    assert equal {fred: "hash-new", jones: "hash-jones"} (open --raw $file | from json)
}


#======================================================================================================================
# remove
#======================================================================================================================

export def remove__deletes_user [] {
    let file = $"(mktemp --directory)/users.json"
    {fred: "a", jones: "b"} | to json | save $file

    with-env {BF_PROXY_USERS: $file} { users remove fred }

    assert equal {jones: "b"} (open --raw $file | from json)
}

export def remove__fails_for_unknown_user [] {
    let file = $"(mktemp --directory)/users.json"
    {fred: "a"} | to json | save $file

    assert error { with-env {BF_PROXY_USERS: $file} { users remove jones } }
}

export def remove__fails_without_users_file [] {
    assert error { with-env {BF_PROXY_USERS: $"(mktemp --directory)/users.json"} { users remove fred } }
}


#======================================================================================================================
# load_users
#======================================================================================================================

export def load_users__is_empty_without_file [] {
    assert equal {} (conf load_users "")
    assert equal {} (conf load_users $"(mktemp --directory)/users.json")
}

export def load_users__reads_file [] {
    let file = $"(mktemp --directory)/users.json"
    {fred: "hash"} | to json | save $file

    assert equal {fred: "hash"} (conf load_users $file)
}
