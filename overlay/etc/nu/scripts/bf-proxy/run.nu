use bf
use generate.nu

# Run preflight checks before starting Caddy
export def preflight []: nothing -> nothing {
    # load environment
    bf env load

    # manually set executing script
    bf env x_set --override run caddy

    # validate configuration
    generate validate (bf env PROXY_CADDY_CONF)

    # if we get here we are ready to start Caddy
    bf write "Starting Caddy in foreground mode."
}
