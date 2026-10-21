use bf
use bf-proxy
use bf-s6
bf env load

# Generate Caddy configuration
def main [] {
    bf-proxy generate
    bf-s6 ch apply_file "10-proxy"

    # return nothing
    return
}
