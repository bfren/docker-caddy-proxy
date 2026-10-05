use bf
use conf.nu

# Keys used by nginx-proxy's conf.json - anything else in a domain means the file is not in the old format
const nginx_proxy_keys = ["primary" "upstream" "aliases" "custom"]

# Returns true if the parsed contents of conf.json are in the old nginx-proxy format:
#   - $schema refers to nginx-proxy (or its ssl-conf-schema.json), or
#   - there is no $schema and every domain only uses keys supported by nginx-proxy
export def is_nginx_proxy [
    json: record    # Parsed contents of conf.json
]: nothing -> bool {
    let schema = $json | get --optional "$schema" | default ""
    if ($schema =~ '(?i)nginx-proxy|ssl-conf-schema') { return true }
    if $schema != "" { return false }

    let domains = $json | get --optional domains | default []
    ($domains | is-not-empty) and ($domains | all {|d| $d | columns | all {|k| $k in $nginx_proxy_keys } })
}

# Convert the parsed contents of an nginx-proxy conf.json to the caddy-proxy format, returning the converted
# configuration and a list of warnings for anything that could not be converted automatically
export def convert [
    json: record                # Parsed contents of conf.json
    --redirect-to-primary (-r)  # Set redirectToPrimary for domains with aliases (nginx PROXY_SSL_REDIRECT_TO_CANONICAL=1)
]: nothing -> record {
    let converted = $json
        | get --optional domains
        | default []
        | each {|d| convert_domain --redirect-to-primary=$redirect_to_primary $d }

    {
        conf: {
            "$schema": $conf.schema
            domains: ($converted | get domain)
        }
        warnings: ($converted | get warnings | flatten)
    }
}

# Convert a single domain, returning the converted domain and a list of warnings
export def convert_domain [
    --redirect-to-primary (-r)  # Set redirectToPrimary if the domain has aliases
    domain: record              # Domain from nginx-proxy conf.json
]: nothing -> record {
    let primary = $domain | get --optional primary | default ""
    let aliases = $domain | get --optional aliases | default []
    let upstream = $domain | get --optional upstream | default ""
    let custom = $domain | get --optional custom | default false

    # keep the supported keys in their usual order, dropping empty values
    mut converted = {primary: $primary}
    if ($aliases | is-not-empty) { $converted = $converted | insert aliases $aliases }
    if $upstream != "" { $converted = $converted | insert upstream $upstream }
    if $redirect_to_primary and ($aliases | is-not-empty) { $converted = $converted | insert redirectToPrimary true }
    if $custom == true { $converted = $converted | insert custom true }

    # warn about anything that cannot be converted automatically
    mut warnings = []
    let unknown = $domain | columns | where {|k| $k not-in $nginx_proxy_keys }
    if ($unknown | is-not-empty) {
        $warnings = $warnings | append $"($primary): removed unsupported keys ($unknown | str join ', ')."
    }
    if $upstream != "" {
        let path = try { $upstream | url parse | get path } catch { "" }
        if $path not-in ["" "/"] {
            $warnings = $warnings | append $"($primary): upstream '($upstream)' includes a path, which is not supported - use a route with stripPrefix, or a custom domain configuration."
        }
    }
    if $custom == true {
        $warnings = $warnings | append $"($primary): custom Nginx configuration cannot be converted - /sites/($primary).json will be generated from the standard configuration for you to customise."
    }

    {domain: $converted, warnings: $warnings}
}

# Detect an nginx-proxy conf.json and convert it in place, keeping a backup of the original file
export def main [
    path: string    # Absolute path to conf.json
]: nothing -> nothing {
    if ($path | bf fs is_not_file) { return }

    let json = try { open --raw $path | from json } catch {
        bf write error $"($path) is not valid JSON." migrate
    }
    if not (is_nginx_proxy $json) { return }

    # nginx-proxy used a global environment variable for canonical redirection, so carry it into conf.json
    bf write $"($path) is in nginx-proxy format - converting." migrate
    let redirect = bf env check --no-prefix PROXY_SSL_REDIRECT_TO_CANONICAL
    let result = convert --redirect-to-primary=$redirect $json

    # back up the original file - never overwrite an earlier backup
    let backup = $"($path).nginx-proxy"
    let backup_path = if ($backup | path exists) { $"($backup).(date now | format date '%Y%m%d%H%M%S')" } else { $backup }
    cp $path $backup_path
    bf write $" .. original saved to ($backup_path)." migrate

    # save converted file
    $result.conf
        | to json --indent 4
        | save --force $path
    $result.warnings | each {|w| bf write warn $" .. ($w)" migrate } | ignore
    bf write ok $" .. converted ($result.conf.domains | length) domain\(s\)." migrate
}
