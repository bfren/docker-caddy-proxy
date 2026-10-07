use bf
use generate.nu

# Reload Caddy configuration - but only if Caddy is running
export def main []: nothing -> nothing {
    let caddy_conf = bf env PROXY_CADDY_CONF

    # if the pid is empty, Caddy is not running
    let pid = { ^pidof caddy } | bf handle -i reload
    if $pid == "" {
        bf write debug "Caddy is not running." reload
        return
    }

    # validate configuration and then reload using the admin API
    generate validate $caddy_conf
    bf write "Reloading Caddy." reload
    { ^caddy reload --config $caddy_conf --address "localhost:2019" } | bf handle -I reload
}
