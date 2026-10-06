use std assert
use ../bf-proxy/autoreload.nu *


#======================================================================================================================
# fingerprint
#======================================================================================================================

# Create a conf.json, users.json and sites directory with a domain file and an extra route, returning their paths
def files []: nothing -> record {
    let dir = mktemp --directory
    mkdir $"($dir)/sites/a.test.d"
    "{}" | save $"($dir)/conf.json"
    "{}" | save $"($dir)/users.json"
    "{}" | save $"($dir)/sites/a.test.json"
    "{}" | save $"($dir)/sites/a.test.d/10.json"
    {conf: $"($dir)/conf.json", users: $"($dir)/users.json", sites: $"($dir)/sites"}
}

export def fingerprint__is_the_same_when_nothing_changes [] {
    let f = files

    assert equal (fingerprint $f) (fingerprint $f)
}

export def fingerprint__does_not_change_as_time_passes [] {
    let f = files
    let before = fingerprint $f

    sleep 1.1sec

    assert equal $before (fingerprint $f)
}

export def fingerprint__changes_when_conf_json_changes [] {
    let f = files
    let before = fingerprint $f

    "{\"domains\": []}" | save --force $f.conf

    assert not equal $before (fingerprint $f)
}

export def fingerprint__changes_when_an_extra_route_is_added [] {
    let f = files
    let before = fingerprint $f

    "{}" | save $"($f.sites)/a.test.d/20.json"

    assert not equal $before (fingerprint $f)
}

export def fingerprint__ignores_other_files [] {
    let f = files
    let before = fingerprint $f

    "x" | save $"($f.sites)/a.test.d/old.conf"

    assert equal $before (fingerprint $f)
}

export def fingerprint__handles_missing_files [] {
    let f = files
    rm $f.users

    assert equal 32 (fingerprint $f | str length)
}
