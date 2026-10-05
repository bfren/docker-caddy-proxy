use bf
use conf.nu
use routes.nu
use tls.nu

# Comment added to generated domain files
const comment_generated = [
    "WARNING: This file is generated. Do not make changes to this file."
    "Changes will be overwritten the next time the container is started or proxy-regenerate is run."
    "To add host names or change the upstream, edit /ssl/conf.json."
    "To add extra routes, add *.json files (each containing a route object or array of routes) to the .d directory."
    "For full control, set \"custom\": true for this domain in /ssl/conf.json - this file will then be left alone."
]

# Comment added to custom domain files
const comment_custom = [
    "You can make changes to this file - it will not be regenerated while \"custom\": true is set in /ssl/conf.json."
    "WARNING: changes could break your site, and you will need to add future bug fixes and features manually."
    "'route' is added to the HTTPS server routes, 'errors' to its error routes, and 'tls' to the TLS automation policies."
    "To return to generated configuration, remove \"custom\": true (or run proxy-regenerate -d <domain> -f)."
]

# Return the path to a domain's configuration file
export def file_path [sites: string, primary: string]: nothing -> string { $"($sites)/($primary).json" }

# Return the path to a domain's directory of extra routes
export def extras_path [sites: string, primary: string]: nothing -> string { $"($sites)/($primary).d" }

# Generate the configuration for a domain
export def generate [
    --before-routes: list<record> = []  # Routes from *.before.json files in the domain's .d directory
    --extra-routes: list<record> = []   # Routes from other *.json files in the domain's .d directory
    domain: record                      # Normalised domain
    opts: record                        # Options record (see conf opts)
]: nothing -> record {
    {
        _comment: (if $domain.custom { $comment_custom } else { $comment_generated })
        route: (routes domain_route --before-routes $before_routes --extra-routes $extra_routes $domain $opts)
        errors: (routes error_route $domain $opts)
        tls: (tls policy (conf hosts $domain) $domain.challenge $opts)
    }
}

# Get the configuration for a domain:
#   - if the configuration file does not exist, it is generated from the standard base
#   - if it exists and the domain is custom, it is left alone and used as it is
#   - otherwise it is regenerated
export def load [
    domain: record  # Normalised domain
    opts: record    # Options record (see conf opts)
    sites: string   # Sites directory
    --force (-f)    # Regenerate the file even if the domain is custom
]: nothing -> record {
    let path = file_path $sites $domain.primary
    let extras = extras_path $sites $domain.primary
    if ($extras | bf fs is_not_dir) { mkdir $extras }

    # nginx-proxy configuration files are not used - only Caddy JSON routes are loaded
    let nginx_files = glob $"($extras)/*.{conf,rules,location,upstream}"
    if ($nginx_files | is-not-empty) {
        bf write warn $" .. ignoring Nginx configuration in ($extras) - add Caddy JSON routes as *.json files instead." sites/load
    }

    # use existing custom configuration
    if $domain.custom and ($path | path exists) and (not $force) {
        bf write debug $" .. keeping custom configuration ($path)." sites/load
        return (read_custom $path)
    }

    # generate configuration
    bf write debug $" .. generating ($path)." sites/load
    let generated = generate $domain $opts
    $generated | to json --indent 4 | save --force $path

    # custom domains are fully controlled by the user via the file, so extra routes only apply to generated domains -
    # they are not saved to the domain file, so it always shows the standard configuration
    if $domain.custom { return $generated }
    let before_routes = load_extras --before $extras
    let extra_routes = load_extras $extras
    if ($before_routes | is-empty) and ($extra_routes | is-empty) { return $generated }

    if ($before_routes | is-not-empty) {
        bf write warn $" .. adding ($before_routes | length) route\(s\) from *.before.json in ($extras) - these are not protected by auth, headers or AI bot blocking." sites/load
    }
    bf write debug $" .. adding ($extra_routes | length) extra route\(s\) from ($extras)." sites/load
    generate --before-routes $before_routes --extra-routes $extra_routes $domain $opts
}

# Read and check a custom domain configuration file
export def read_custom [path: string]: nothing -> record {
    let json = try { open --raw $path | from json } catch {
        bf write error $"Custom configuration ($path) is not valid JSON." sites/read_custom
    }
    if ($json | get --optional route) == null {
        bf write error $"Custom configuration ($path) must contain a 'route' object." sites/read_custom
    }
    $json
}

# Load extra routes from *.json files in a domain's .d directory (sorted by name)
export def load_extras [
    --before (-b)   # Load *.before.json files (otherwise all other *.json files are loaded)
    dir: string     # The domain's .d directory
]: nothing -> list<record> {
    if ($dir | bf fs is_not_dir) { return [] }
    let files = glob $"($dir)/*.json"
        | where {|f| ($f | str ends-with ".before.json") == $before }
        | sort --natural
    $files | each {|f|
        let json = try {
            open --raw $f | from json
        } catch {
            bf write error $"($f) is not valid JSON." sites/load_extras
        }
        if ($json | describe | str starts-with "list") { $json } else { [$json] }
    } | reduce --fold [] {|it, acc| $acc | append $it }
}
