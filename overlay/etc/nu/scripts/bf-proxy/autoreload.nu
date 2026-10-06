use bf
use generate.nu
use reload.nu

# Regenerate configuration and reload Caddy - called by the proxy-autoreload service when configuration files change;
# an invalid change is reported and the current configuration is kept
export def main []: nothing -> nothing {
    bf env load
    bf env x_set --override autoreload

    bf write "Configuration has changed - regenerating." autoreload
    try {
        generate
        bf ch apply_file "20-proxy"
        reload
    } catch {
        bf write notok "Configuration has not been reloaded - fix the errors above and save again." autoreload
    }
}
