use bf
use bf-proxy
use bf-s6
bf env load

# Create and update PEM files for other containers now, then every 15 minutes to pick up new and renewed certificates
def main [] {
    let hosts = bf-proxy pem conf_hosts (bf-proxy conf read)
    bf-proxy pem sync (bf env PROXY_STORAGE) (bf env PROXY_CERTS) $hosts
    bf-s6 crontab add --min "*/15" "proxy-pem"
}
