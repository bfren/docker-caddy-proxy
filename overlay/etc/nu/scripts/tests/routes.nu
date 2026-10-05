use std assert
use ../bf-proxy/conf.nu
use ../bf-proxy/routes.nu *
use helpers.nu

# Get the subroute routes for a domain route
def subroutes [route: record]: nothing -> list<record> { $route.handle.0.routes }


#======================================================================================================================
# parse_upstream
#======================================================================================================================

export def parse_upstream__uses_default_ports [] {
    assert equal {dial: "app:80", tls: false} (parse_upstream "http://app")
    assert equal {dial: "app:443", tls: true} (parse_upstream "https://app")
}

export def parse_upstream__uses_specified_port [] {
    assert equal {dial: "app:5000", tls: false} (parse_upstream "http://app:5000")
    assert equal {dial: "10.0.0.1:8443", tls: true} (parse_upstream "https://10.0.0.1:8443/")
}


#======================================================================================================================
# reverse_proxy
#======================================================================================================================

export def reverse_proxy__single_http_upstream [] {
    let result = reverse_proxy ["http://app:5000"] "random" "/www/public"

    assert equal "reverse_proxy" $result.handler
    assert equal [{dial: "app:5000"}] $result.upstreams
    assert equal null ($result | get --optional transport)
    assert equal null ($result | get --optional load_balancing)
    assert equal [502 503 504] $result.handle_response.0.match.status_code
}

export def reverse_proxy__https_upstream_uses_tls_transport [] {
    let result = reverse_proxy ["https://app"] "random" "/www/public"

    assert equal {protocol: "http", tls: {}} $result.transport
}

export def reverse_proxy__multiple_upstreams_use_load_balancing [] {
    let result = reverse_proxy ["http://a" "http://b"] "round_robin" "/www/public"

    assert equal [{dial: "a:80"} {dial: "b:80"}] $result.upstreams
    assert equal "round_robin" $result.load_balancing.selection_policy.policy
}


#======================================================================================================================
# headers_handler
#======================================================================================================================

export def headers_handler__adds_secure_headers [] {
    let result = headers_handler {}

    assert equal ["SAMEORIGIN"] ($result.response.set | get "X-Frame-Options")
    assert equal ["max-age=63072000"] ($result.response.set | get "Strict-Transport-Security")
}

export def headers_handler__custom_headers_override_and_extend [] {
    let result = headers_handler {"X-Frame-Options": "DENY", "X-Extra": "1"}

    assert equal ["DENY"] ($result.response.set | get "X-Frame-Options")
    assert equal ["1"] ($result.response.set | get "X-Extra")
}


export def headers_handler__adds_clacks_header_when_enabled [] {
    let with = headers_handler --clacks {}
    let without = headers_handler {}

    assert equal ["GNU Terry Pratchett"] ($with.response.set | get "X-Clacks-Overhead")
    assert equal null ($without.response.set | get --optional "X-Clacks-Overhead")
}

export def domain_route__adds_clacks_header_by_default [] {
    let result = domain_route (helpers domain) (helpers opts) | to json

    assert str contains $result "GNU Terry Pratchett"
}

export def domain_route__does_not_add_clacks_header_when_disabled [] {
    let d = conf normalise {primary: "a.test", upstream: "http://a", clacks: false} (helpers opts)

    let result = domain_route $d (helpers opts) | to json

    assert not ($result =~ "X-Clacks-Overhead")
}

export def proxy_domain_route__adds_clacks_header [] {
    let result = proxy_domain_route (helpers opts) | to json

    assert str contains $result "GNU Terry Pratchett"
}


#======================================================================================================================
# auth_handler
#======================================================================================================================

export def auth_handler__true_uses_all_users [] {
    let users = {bob: "hash1", alice: "hash2"}

    let result = auth_handler true $users

    assert equal ["bob" "alice"] ($result.providers.http_basic.accounts | get username)
}

export def auth_handler__list_uses_named_users [] {
    let users = {bob: "hash1", alice: "hash2"}

    let result = auth_handler ["alice"] $users

    assert equal [{username: "alice", password: "hash2"}] $result.providers.http_basic.accounts
}


#======================================================================================================================
# domain_route
#======================================================================================================================

export def domain_route__matches_primary_and_aliases [] {
    let d = conf normalise {primary: "a.test", upstream: "http://a", aliases: ["www.a.test"]} (helpers opts)

    let result = domain_route $d (helpers opts)

    assert equal [{host: ["a.test" "www.a.test"]}] $result.match
    assert equal true $result.terminal
    assert equal "subroute" $result.handle.0.handler
}

export def domain_route__redirects_aliases_to_primary_when_enabled [] {
    let d = conf normalise {primary: "a.test", upstream: "http://a", aliases: ["www.a.test"], redirectToPrimary: true} (helpers opts)

    let first = domain_route $d (helpers opts) | subroutes $in | first

    assert equal [{not: [{host: ["a.test"]}]}] $first.match
    assert equal ["https://a.test{http.request.uri}"] $first.handle.0.headers.Location
}

export def domain_route__does_not_redirect_without_aliases [] {
    let d = conf normalise {primary: "a.test", upstream: "http://a", redirectToPrimary: true} (helpers opts)

    let result = domain_route $d (helpers opts) | subroutes $in

    assert not ($result | any {|r| ($r | get --optional match | default [] | to json) =~ "not" })
}

export def domain_route__blocks_ai_bots_when_enabled [] {
    let d = helpers domain
    let enabled = domain_route $d (helpers opts) | subroutes $in
    let disabled = domain_route $d (helpers opts | update block_ai_bots false) | subroutes $in

    assert ($enabled | any {|r| ($r | to json) =~ "GPTBot" })
    assert not ($disabled | any {|r| ($r | to json) =~ "GPTBot" })
}

export def domain_route__does_not_block_ai_bots_when_list_is_empty [] {
    let result = domain_route (helpers domain) (helpers opts | update ai_bots []) | subroutes $in

    assert not ($result | any {|r| ($r | to json) =~ "header_regexp" })
}

export def domain_route__default_upstream_is_last [] {
    let routes = [{path: "/api/*", upstream: "http://api", stripPrefix: "/api"}]
    let d = conf normalise {primary: "a.test", upstream: "http://a", routes: $routes} (helpers opts)

    let result = domain_route $d (helpers opts) | subroutes $in
    let api = $result | get (($result | length) - 2)
    let last = $result | last

    assert equal [{path: ["/api/*"]}] $api.match
    assert equal {handler: "rewrite", strip_path_prefix: "/api"} $api.handle.0
    assert equal [{dial: "api:80"}] $api.handle.1.upstreams
    assert equal [{dial: "a:80"}] $last.handle.0.upstreams
}

export def domain_route__adds_auth_when_enabled [] {
    let d = conf normalise {primary: "a.test", upstream: "http://a", auth: true} (helpers opts)

    let result = domain_route $d (helpers opts) | to json

    assert str contains $result "http_basic"
}


#======================================================================================================================
# custom_route
#======================================================================================================================

export def custom_route__redirect [] {
    let result = custom_route {path: "/old/*", redirect: "https://a.test/new", status: 302} "/www/public"

    assert equal 302 $result.handle.0.status_code
    assert equal ["https://a.test/new"] $result.handle.0.headers.Location
}

export def custom_route__file_server [] {
    let result = custom_route {path: "/files/*", root: "/www/files"} "/www/public"

    assert equal {handler: "file_server", root: "/www/files"} $result.handle.0
}

export def custom_route__without_path_matches_everything [] {
    let result = custom_route {upstream: "http://a"} "/www/public"

    assert equal null ($result | get --optional match)
}


#======================================================================================================================
# error_route / catch_all_route
#======================================================================================================================

export def error_route__matches_hosts_and_maintenance_codes [] {
    let result = error_route (helpers domain "a.test") (helpers opts)

    assert equal ["a.test"] $result.match.0.host
    assert equal "{http.error.status_code} in [502, 503, 504]" $result.match.0.expression
}

export def catch_all_route__redirects_to_proxy_domain [] {
    let result = catch_all_route (helpers opts)

    assert equal ["https://proxy.test{http.request.uri}"] $result.handle.0.headers.Location
}
