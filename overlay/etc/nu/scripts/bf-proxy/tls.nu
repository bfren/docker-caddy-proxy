# Let's Encrypt ACME directories
export const lets_encrypt_live = "https://acme-v02.api.letsencrypt.org/directory"
export const lets_encrypt_staging = "https://acme-staging-v02.api.letsencrypt.org/directory"

# DNS provider modules - tokens are placeholders replaced by Caddy at runtime, so they are never written to the
# configuration file
export const dns_providers = {
    desec: {name: "desec", token: "{env.BF_PROXY_DESEC_TOKEN}"}
    hetzner: {name: "hetzner", api_token: "{env.BF_PROXY_HETZNER_TOKEN}"}
}

# Build the DNS challenge configuration using the configured DNS provider
export def dns_challenge [
    --override-domain: string = ""  # Create the TXT record here instead of _acme-challenge.<host> (see dnsOverrideDomain)
    opts: record                    # Options record (see conf opts)
]: nothing -> record {
    mut dns = {provider: ($dns_providers | get $opts.dns_provider)}
    if $opts.dns_ttl != "" { $dns = $dns | insert ttl $opts.dns_ttl }
    if $override_domain != "" { $dns = $dns | insert override_domain $override_domain }
    if $opts.dns_propagation_delay != "" { $dns = $dns | insert propagation_delay $opts.dns_propagation_delay }
    if $opts.dns_propagation_timeout != "" { $dns = $dns | insert propagation_timeout $opts.dns_propagation_timeout }
    if ($opts.dns_resolvers | is-not-empty) { $dns = $dns | insert resolvers $opts.dns_resolvers }
    $dns
}

# Build the certificate issuer for the given challenge type
export def issuer [
    --dns-override: string = "" # DNS challenge override domain (see dns_challenge)
    challenge: string           # 'http' or 'dns'
    opts: record                # Options record (see conf opts)
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
            dns: (dns_challenge --override-domain $dns_override $opts)
        }
    } else { $base }
}

# Build a TLS automation policy for a list of subjects (host names)
export def policy [
    --dns-override: string = "" # DNS challenge override domain (see dns_challenge)
    subjects: list<string>      # Host names covered by the policy - if empty, the policy applies to all other names
    challenge: string           # 'http' or 'dns'
    opts: record                # Options record (see conf opts)
]: nothing -> record {
    let p = {issuers: [(issuer --dns-override $dns_override $challenge $opts)]}
    if ($subjects | is-empty) { $p } else { {subjects: $subjects} | merge $p }
}

# Build the TLS connection policies for the HTTPS server
export def connection_policies [opts: record]: nothing -> list<record> {
    let p = {fallback_sni: $opts.proxy_domain}
    [(if $opts.harden { $p | insert protocol_min "tls1.3" } else { $p })]
}
