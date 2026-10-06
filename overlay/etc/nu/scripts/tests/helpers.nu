use ../bf-proxy/conf.nu

# Options record used by tests - equivalent to the defaults set in the Dockerfile
export def opts []: nothing -> record {
    {
        proxy_domain: "proxy.test"
        email: "test@proxy.test"
        live: false
        internal_ca: false
        challenge: "http"
        retry: "5s"
        dns_propagation_delay: ""
        dns_propagation_timeout: ""
        dns_resolvers: []
        harden: false
        redirect_to_primary: false
        block_ai_bots: true
        ai_bots: ["GPTBot" "CCBot" "Brightbot 1.0"]
        access_log: false
        public: "/www/public"
        storage: "/ssl/caddy"
        users: {bob: "$2a$14$Zkx19XLiW6VYouLHR5NmfOFU0z2GTNmpkT/5qqR7hx4IjWJPDhjvG"}
    }
}

# A normalised domain with the minimum required values set
export def domain [primary: string = "example.test"]: nothing -> record {
    conf normalise {primary: $primary, upstream: "http://app:5000"} (opts)
}
