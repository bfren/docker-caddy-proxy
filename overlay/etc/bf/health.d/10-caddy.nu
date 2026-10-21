use bf
use bf-proxy/conf.nu
bf env load -x

# Check Caddy is serving requests using the local health check server (which, unlike the admin API, is not logged)
def main [] { $"http://($conf.health_listen)/" | bf http test | if not $in { exit 1 } }
