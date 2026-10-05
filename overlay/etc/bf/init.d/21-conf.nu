use bf
use bf-proxy migrate
bf env load

# Clean existing configuration (if requested), convert an nginx-proxy conf.json (if found),
# and generate conf.json from environment variables (if set)
def main [] {
    # remove all generated configuration and certificates
    if (bf env check PROXY_CLEAN_INSTALL) {
        bf write "Clean install requested - removing domain configuration and certificates."
        [
            (glob $"(bf env PROXY_SITES)/*")
            (bf env PROXY_STORAGE)
            (bf env PROXY_CADDY_CONF)
        ] | each { rm --force --recursive $in }
    }

    # if conf.json already exists, convert it from nginx-proxy format if necessary - then there is nothing more to do
    let conf = bf env PROXY_CONF
    if ($conf | path exists) {
        migrate $conf
        return
    }

    # if the auto variables are not set there is nothing more to do
    let primary = bf env --safe PROXY_AUTO_PRIMARY
    let upstream = bf env --safe PROXY_AUTO_UPSTREAM
    if $primary == "" or $upstream == "" { return }

    # generate conf.json
    bf write $"Generating ($conf) using auto environment variables."
    let aliases = bf env --safe PROXY_AUTO_ALIASES
        | split row " "
        | where $it != ""
    let domain = {primary: $primary, upstream: $upstream}
        | merge (if ($aliases | is-empty) { {} } else { {aliases: $aliases, redirectToPrimary: true} })
        | merge (if (bf env check PROXY_AUTO_CUSTOM) { {custom: true} } else { {} })

    {
        "$schema": "https://raw.githubusercontent.com/bfren/docker-caddy-proxy/main/proxy-conf-schema.json"
        domains: [$domain]
    }
        | to json --indent 4
        | save $conf

    # return nothing
    return
}
