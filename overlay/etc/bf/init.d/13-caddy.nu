use bf
use bf-proxy
use bf-proxy/conf.nu
use bf-s6
bf env load

# Generate Caddy configuration, and create the directory for the admin API socket (ownership set by ch.d/10-proxy)
def main [] {
    mkdir $conf.admin_dir
    bf-proxy generate
    bf-s6 ch apply_file "10-proxy"

    # return nothing
    return
}
