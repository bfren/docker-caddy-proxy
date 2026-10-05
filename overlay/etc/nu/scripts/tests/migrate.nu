use std assert
use ../bf-proxy/conf.nu
use ../bf-proxy/migrate.nu *
use helpers.nu

# nginx-proxy conf.json, as in its ssl-conf-sample.json
def nginx_proxy_conf []: nothing -> record {
    {
        "$schema": "https://schemas.bfren.dev/docker/nginx-proxy/domains.json"
        domains: [
            {primary: "example.com", upstream: "http://example:5000", aliases: ["www.example.com" "ex.com"], custom: true}
            {primary: "test.com", upstream: "http://test", aliases: ["www.test.com"]}
        ]
    }
}


#======================================================================================================================
# is_nginx_proxy
#======================================================================================================================

export def is_nginx_proxy__true_for_nginx_proxy_schemas [] {
    assert (is_nginx_proxy (nginx_proxy_conf))
    assert (is_nginx_proxy {"$schema": "https://raw.githubusercontent.com/bfren/docker-nginx-proxy/main/ssl-conf-schema.json", domains: []})
}

export def is_nginx_proxy__true_without_schema_when_only_old_keys_are_used [] {
    assert (is_nginx_proxy {domains: [{primary: "a.test", upstream: "http://a", aliases: ["b.test"]}]})
}

export def is_nginx_proxy__false_for_caddy_proxy_schema [] {
    assert not (is_nginx_proxy {"$schema": $conf.schema, domains: [{primary: "a.test", upstream: "http://a"}]})
}

export def is_nginx_proxy__false_without_schema_when_new_keys_are_used [] {
    assert not (is_nginx_proxy {domains: [{primary: "a.test", upstream: "http://a", challenge: "dns"}]})
}

export def is_nginx_proxy__false_without_schema_or_domains [] {
    assert not (is_nginx_proxy {domains: []})
}


#======================================================================================================================
# convert
#======================================================================================================================

export def convert__sets_caddy_proxy_schema [] {
    let result = convert (nginx_proxy_conf)

    assert equal $conf.schema ($result.conf | get "$schema")
}

export def convert__keeps_domains [] {
    let result = convert (nginx_proxy_conf)

    assert equal ["example.com" "test.com"] ($result.conf.domains | get primary)
    assert equal ["www.example.com" "ex.com"] ($result.conf.domains.0.aliases)
    assert equal "http://example:5000" $result.conf.domains.0.upstream
    assert equal true $result.conf.domains.0.custom
    assert equal null ($result.conf.domains.1 | get --optional custom)
}

export def convert__converted_configuration_loads_and_validates [] {
    let opts = helpers opts
    let path = mktemp --suffix .json
    convert (nginx_proxy_conf) | get conf | to json | save --force $path

    let domains = conf load $path $opts
    let errors = conf validate $domains $opts

    assert equal [] $errors
}

export def convert__warns_about_custom_domains [] {
    let result = convert (nginx_proxy_conf)

    assert equal 1 ($result.warnings | length)
    assert str contains ($result.warnings | first) "example.com: custom Nginx configuration"
}

export def convert__warns_about_upstream_paths_and_unknown_keys [] {
    let result = convert {domains: [{primary: "a.test", upstream: "http://a/sub", extra: 1}]}

    assert equal 2 ($result.warnings | length)
    assert equal null ($result.conf.domains.0 | get --optional extra)
}


#======================================================================================================================
# main
#======================================================================================================================

export def main__converts_file_and_keeps_backup [] {
    let dir = mktemp --directory
    let path = $"($dir)/conf.json"
    nginx_proxy_conf | to json | save $path
    let original = open --raw $path

    main $path

    assert equal $original (open --raw $"($path).nginx-proxy")
    assert equal $conf.schema (open $path | get "$schema")
}

export def main__does_not_change_caddy_proxy_file [] {
    let dir = mktemp --directory
    let path = $"($dir)/conf.json"
    {"$schema": $conf.schema, domains: [{primary: "a.test", upstream: "http://a", challenge: "dns"}]} | to json | save $path
    let original = open --raw $path

    main $path

    assert equal $original (open --raw $path)
    assert not ($"($path).nginx-proxy" | path exists)
}

export def main__does_not_overwrite_existing_backup [] {
    let dir = mktemp --directory
    let path = $"($dir)/conf.json"
    "earlier backup" | save $"($path).nginx-proxy"
    nginx_proxy_conf | to json | save $path

    main $path

    assert equal "earlier backup" (open --raw $"($path).nginx-proxy")
    assert equal 2 (glob $"($path).nginx-proxy*" | length)
}
