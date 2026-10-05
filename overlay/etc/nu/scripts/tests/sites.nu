use std assert
use ../bf-proxy/conf.nu
use ../bf-proxy/sites.nu *
use helpers.nu


#======================================================================================================================
# load
#======================================================================================================================

export def load__generates_file_when_it_does_not_exist [] {
    let dir = mktemp --directory
    let d = helpers domain "a.test"

    let result = load $d (helpers opts) $dir

    assert (($"($dir)/a.test.json") | path exists)
    assert (($"($dir)/a.test.d") | path exists)
    assert equal ["_comment" "route" "errors" "tls"] ($result | columns)
}

export def load__generates_file_for_custom_domain_when_it_does_not_exist [] {
    let dir = mktemp --directory
    let d = conf normalise {primary: "a.test", upstream: "http://a", custom: true} (helpers opts)

    load $d (helpers opts) $dir

    assert (($"($dir)/a.test.json") | path exists)
}

export def load__keeps_existing_custom_file [] {
    let dir = mktemp --directory
    let path = $"($dir)/a.test.json"
    let custom = {route: {handle: [{handler: "static_response", body: "custom"}]}, tls: {subjects: ["a.test"]}}
    $custom | to json | save $path
    let before = open --raw $path
    let d = conf normalise {primary: "a.test", upstream: "http://a", custom: true} (helpers opts)

    let result = load $d (helpers opts) $dir

    assert equal $before (open --raw $path)
    assert equal "custom" $result.route.handle.0.body
}

export def load__regenerates_existing_file_when_not_custom [] {
    let dir = mktemp --directory
    let path = $"($dir)/a.test.json"
    {route: {handle: [{handler: "static_response", body: "edited"}]}} | to json | save $path
    let d = helpers domain "a.test"

    let result = load $d (helpers opts) $dir

    assert not ((open --raw $path) =~ "edited")
    assert equal "subroute" $result.route.handle.0.handler
}

export def load__force_regenerates_custom_file [] {
    let dir = mktemp --directory
    let path = $"($dir)/a.test.json"
    {route: {handle: [{handler: "static_response", body: "custom"}]}} | to json | save $path
    let d = conf normalise {primary: "a.test", upstream: "http://a", custom: true} (helpers opts)

    let result = load --force $d (helpers opts) $dir

    assert not ((open --raw $path) =~ "custom\"")
    assert equal "subroute" $result.route.handle.0.handler
}

export def load__adds_extra_routes_before_the_default_upstream [] {
    let dir = mktemp --directory
    mkdir $"($dir)/a.test.d"
    {match: [{path: ["/extra"]}], handle: [{handler: "static_response", body: "extra"}]} | to json | save $"($dir)/a.test.d/10-extra.json"
    let d = helpers domain "a.test"

    let routes = load $d (helpers opts) $dir | get route.handle.0.routes
    let extra = $routes | enumerate | where {|x| ($x.item | to json) =~ '"extra"' } | first

    assert equal (($routes | length) - 2) $extra.index
    assert equal "reverse_proxy" ($routes | last | get handle.0.handler)
    assert not ((open --raw $"($dir)/a.test.json") =~ '"extra"')
}


#======================================================================================================================
# read_custom / load_extras
#======================================================================================================================

export def read_custom__requires_route [] {
    let path = mktemp --suffix .json
    {tls: {}} | to json | save --force $path

    let result = try { read_custom $path ; "no error" } catch { "error" }

    assert equal "error" $result
}

export def load_extras__loads_objects_and_arrays_in_name_order [] {
    let dir = mktemp --directory
    [{handle: [{body: "b"}]} {handle: [{body: "c"}]}] | to json | save $"($dir)/20.json"
    {handle: [{body: "a"}]} | to json | save $"($dir)/10.json"

    let result = load_extras $dir

    assert equal ["a" "b" "c"] ($result | each {|r| $r.handle.0.body })
}
