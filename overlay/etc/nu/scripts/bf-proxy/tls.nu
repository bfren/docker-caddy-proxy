# Let's Encrypt ACME directories
export const lets_encrypt_live = "https://acme-v02.api.letsencrypt.org/directory"
export const lets_encrypt_staging = "https://acme-staging-v02.api.letsencrypt.org/directory"

# Placeholder replaced by Caddy at runtime, so the token is never written to the configuration file
export const desec_token = "{env.BF_PROXY_DESEC_TOKEN}"

# Build the DNS challenge configuration using the deSEC provider
export def dns_challenge [opts: record]: nothing -> record {
    mut dns = {provider: {name: "desec", token: $desec_token}}
    if $opts.dns_propagation_delay != "" { $dns = $dns | insert propagation_delay $opts.dns_propagation_delay }
    if $opts.dns_propagation_timeout != "" { $dns = $dns | insert propagation_timeout $opts.dns_propagation_timeout }
    if ($opts.dns_resolvers | is-not-empty) { $dns = $dns | insert resolvers $opts.dns_resolvers }
    $dns
}

# Build the certificate issuer for the given challenge type
export def issuer [
    challenge: string   # 'http' or 'dns'
    opts: record        # Options record (see conf opts)
]: nothing -> record {
    # use Caddy's internal CA (for testing / local development)
    if $opts.internal_ca { return {module: "internal"} }

    let base = {
        module: "acme"
        ca: (if $opts.live { $lets_encrypt_live } else { $lets_encrypt_staging })
        email: $opts.email
    }

    # disable the HTTP and TLS-ALPN challenges when using DNS, so only DNS is attempted
    if $challenge == "dns" {
        $base | insert challenges {
            http: {disabled: true}
            tls-alpn: {disabled: true}
            dns: (dns_challenge $opts)
        }
    } else { $base }
}

# Build a TLS automation policy for a list of subjects (host names)
export def policy [
    subjects: list<string>  # Host names covered by the policy - if empty, the policy applies to all other names
    challenge: string       # 'http' or 'dns'
    opts: record            # Options record (see conf opts)
]: nothing -> record {
    let p = {issuers: [(issuer $challenge $opts)]}
    if ($subjects | is-empty) { $p } else { {subjects: $subjects} | merge $p }
}

# Build the TLS connection policies for the HTTPS server
export def connection_policies [opts: record]: nothing -> list<record> {
    let p = {fallback_sni: $opts.proxy_domain}
    [(if $opts.harden { $p | insert protocol_min "tls1.3" } else { $p })]
}
