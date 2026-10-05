use bf
bf env load

# Set environment variables
def main [] {
    let ssl = "/ssl"
    bf env set PROXY_SSL $ssl
    bf env set PROXY_CONF $"($ssl)/conf.json"
    bf env set PROXY_USERS $"($ssl)/users.json"
    bf env set PROXY_STORAGE $"($ssl)/caddy"

    bf env set PROXY_SITES "/sites"
    bf env set PROXY_PUBLIC "/www/public"
    bf env set PROXY_CADDY_CONF "/etc/caddy/caddy.json"

    # return nothing
    return
}
