use std/assert
use ../bf-proxy/pem.nu *
use helpers.nu


#======================================================================================================================
# conf_hosts
#======================================================================================================================

export def conf_hosts__returns_proxy_domain_primaries_and_aliases [] {
    let config = {
        opts: (helpers opts)
        domains: [
            (helpers domain "a.test" | update aliases ["www.a.test" "*.a.test"])
            (helpers domain "b.test")
        ]
    }

    let result = conf_hosts $config

    assert equal ["proxy.test" "a.test" "www.a.test" "*.a.test" "b.test"] $result
}


#======================================================================================================================
# placeholders
#======================================================================================================================

export def placeholders__creates_empty_files_using_storage_names [] {
    let dir = mktemp --directory

    let result = placeholders $dir ["a.test" "*.a.test"]
    let sizes = $result | each {|x| ls $x | first | get size | into int }

    rm --recursive $dir
    assert equal [$"($dir)/a.test/a.test.pem" $"($dir)/wildcard_.a.test/wildcard_.a.test.pem"] $result
    assert equal [0 0] $sizes
}

export def placeholders__leaves_existing_files_and_directories_alone [] {
    let dir = mktemp --directory
    mkdir $"($dir)/a.test" $"($dir)/b.test/b.test.pem"
    "PEM\n" | save $"($dir)/a.test/a.test.pem"

    let result = placeholders $dir ["a.test" "b.test"]
    let saved = open --raw $"($dir)/a.test/a.test.pem"

    rm --recursive $dir
    assert equal [] $result
    assert equal "PEM\n" $saved
}


#======================================================================================================================
# latest
#======================================================================================================================

export def latest__returns_one_certificate_per_name [] {
    let certs = [
        {name: "a.test", ca: "staging", not_after: "2026-01-01T00:00:00Z"}
        {name: "b.test", ca: "live", not_after: "2026-03-01T00:00:00Z"}
        {name: "a.test", ca: "live", not_after: "2026-02-01T00:00:00Z"}
    ]

    let result = $certs | latest

    assert equal ["a.test" "b.test"] ($result | get name | sort)
}

export def latest__returns_certificate_that_expires_last [] {
    let certs = [
        {name: "a.test", ca: "staging", not_after: "2026-03-01T00:00:00Z"}
        {name: "a.test", ca: "live", not_after: "2026-01-01T00:00:00Z"}
    ]

    let result = $certs | latest

    assert equal "staging" ($result | first | get ca)
}


#======================================================================================================================
# file
#======================================================================================================================

export def file__returns_host_directory_and_file [] {
    assert equal "/ssl/certs/a.test/a.test.pem" (file "/ssl/certs" "a.test")
}


#======================================================================================================================
# contents
#======================================================================================================================

export def contents__returns_key_then_certificate [] {
    let dir = mktemp --directory
    "KEY" | save $"($dir)/a.test.key"
    "CERT\nCHAIN\n" | save $"($dir)/a.test.crt"

    let result = contents $"($dir)/a.test.crt"

    rm --recursive $dir
    assert equal "KEY\nCERT\nCHAIN\n" $result
}


#======================================================================================================================
# write
#======================================================================================================================

export def write__creates_file_and_returns_path [] {
    let dir = mktemp --directory
    let pem = $"($dir)/a.test/a.test.pem"

    let result = write $pem "PEM\n"
    let saved = open --raw $pem

    rm --recursive $dir
    assert equal $pem $result
    assert equal "PEM\n" $saved
}

export def write__does_not_write_unchanged_file [] {
    let dir = mktemp --directory
    let pem = $"($dir)/a.test.pem"
    "PEM\n" | save $pem

    let result = write $pem "PEM\n"

    rm --recursive $dir
    assert equal null $result
}

export def write__keeps_inode_when_rewriting [] {
    let dir = mktemp --directory
    let pem = $"($dir)/a.test.pem"
    "OLD\n" | save $pem
    let before = ^stat -c "%i" $pem

    write $pem "NEW\n"
    let after = ^stat -c "%i" $pem
    let saved = open --raw $pem

    rm --recursive $dir
    assert equal $before $after
    assert equal "NEW\n" $saved
}

export def write__fills_empty_placeholder [] {
    let dir = mktemp --directory
    let pem = $"($dir)/a.test.pem"
    "" | save $pem

    let result = write $pem "PEM\n"
    let saved = open --raw $pem

    rm --recursive $dir
    assert equal $pem $result
    assert equal "PEM\n" $saved
}

export def write__does_not_write_to_directory [] {
    let dir = mktemp --directory
    let pem = $"($dir)/a.test.pem"
    mkdir $pem

    let result = write $pem "PEM\n"

    rm --recursive $dir
    assert equal null $result
}
