use bf
use bf-proxy
bf env load

# Generate Caddy configuration
def main [] {
    bf-proxy generate
    bf ch apply_file "20-proxy"

    # return nothing
    return
}
