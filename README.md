# Docker Caddy Proxy

![GitHub release (latest by date)](https://img.shields.io/github/v/release/bfren/docker-caddy-proxy) ![Docker Pulls](https://img.shields.io/endpoint?url=https%3A%2F%2Fbfren.dev%2Fdocker%2Fpulls%2Fcaddy-proxy) ![Docker Image Size](https://img.shields.io/endpoint?url=https%3A%2F%2Fbfren.dev%2Fdocker%2Fsize%2Fcaddy-proxy) ![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/bfren/docker-caddy-proxy/dev.yml?branch=main)

[Docker Repository](https://hub.docker.com/r/bfren/caddy-proxy) - [bfren ecosystem](https://github.com/bfren/docker)

Reverse proxy built on [Caddy](https://caddyserver.com), configured using a simple JSON file.  Caddy requests and renews SSL certificates from Let's Encrypt automatically, using either the HTTP challenge or the DNS challenge (via [deSEC](https://desec.io)), which also supports wildcard certificates.

This is the successor to [bfren/nginx-proxy](https://github.com/bfren/docker-nginx-proxy) - see [Migrating from nginx-proxy](#migrating-from-nginx-proxy).

## Contents

* [Ports](#ports)
* [Volumes](#volumes)
* [Environment Variables](#environment-variables)
* [Configuration](#configuration)
* [Custom Domain Configuration](#custom-domain-configuration)
* [DNS Challenge](#dns-challenge)
* [Helper Functions](#helper-functions)
* [Migrating from nginx-proxy](#migrating-from-nginx-proxy)
* [Licence / Copyright](#licence)

## Ports

Ports 80 and 443 need mapping from the host to your proxy container, e.g. adding `"0.0.0.0:80:80"` to the ports section of your docker compose file.  Port 80 is needed for the HTTP challenge and to redirect HTTP to HTTPS.  Map `443/udp` as well to enable HTTP/3.

Caddy runs as the `www` user (UID 1000), not root, and no extra capabilities are needed: Docker allows unprivileged users to bind to ports below 1024 inside a container by default.  If you use host networking (`network_mode: host`) the host's setting applies instead, so you will need to set `net.ipv4.ip_unprivileged_port_start=80` (or lower) on the host.

* 80
* 443
* 443/udp

## Volumes

| Volume   | Purpose                                                                                                                                                    |
| -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/ssl`   | Your `conf.json` file (see `proxy-conf-sample.json`), basic auth users (`users.json`), and Caddy's certificates and ACME account data (in `/ssl/caddy`). |
| `/sites` | Per-domain Caddy configuration, generated from `conf.json` - see [Custom Domain Configuration](#custom-domain-configuration).                               |
| `/www`   | `/www/public` is served for `BF_PROXY_DOMAIN`, and contains the maintenance page shown when upstream servers are unavailable.                               |

Files and directories in all three volumes are owned by `www` (UID / GID 1000), so they can be edited by the main user account on the host.

## Environment Variables

| Variable                               | Values                | Description                                                                                                    | Default               |
| -------------------------------------- | --------------------- | -------------------------------------------------------------------------------------------------------------- | --------------------- |
| `BF_PROXY_DOMAIN`                      | Domain name           | The domain of the proxy server - requests for unknown hosts are redirected here.                               | *None* - **required** |
| `BF_PROXY_LETS_ENCRYPT_EMAIL`          | Email address         | Used by Let's Encrypt for account registration and notification emails.                                        | *None* - **required** |
| `BF_PROXY_LETS_ENCRYPT_LIVE`           | 0 or 1                | Only set to 1 (to request live certificates) when your config is correct - Let's Encrypt rate limits requests. | 0                     |
| `BF_PROXY_ACME_CHALLENGE`              | http or dns           | Default challenge type - can be overridden per domain in `conf.json`.                                          | http                  |
| `BF_PROXY_DESEC_TOKEN`                 | deSEC API token       | Required to use the DNS challenge - see [DNS Challenge](#dns-challenge).                                       | *None*                |
| `BF_PROXY_DNS_PROPAGATION_DELAY`       | Duration, e.g. 60s    | Time to wait after creating the DNS record before checking for propagation.                                    | *None*                |
| `BF_PROXY_DNS_PROPAGATION_TIMEOUT`     | Duration, e.g. 5m     | How long to wait for DNS propagation.                                                                          | *None*                |
| `BF_PROXY_DNS_RESOLVERS`               | Space-separated IPs   | DNS resolvers used to check propagation, e.g. `1.1.1.1 9.9.9.9`.                                               | *None*                |
| `BF_PROXY_SSL_REDIRECT_TO_CANONICAL`   | 0 or 1                | Default for `redirectToPrimary` - if 1, aliases are redirected to the primary domain.                          | 0                     |
| `BF_PROXY_HARDEN`                      | 0 or 1                | If 1, only TLS 1.3 will be allowed (some older devices may not be able to connect).                            | 0                     |
| `BF_PROXY_BLOCK_AI_BOTS`               | 0 or 1                | If 1, requests from AI crawlers that collect training data receive 403 Forbidden - see below.                 | 1                     |
| `BF_PROXY_ACCESS_LOG`                  | 0 or 1                | If 1, access logs are written to the container output.                                                         | 0                     |
| `BF_PROXY_CLEAN_INSTALL`               | 0 or 1                | If 1, all domain configuration and certificates are deleted on startup.                                        | 0                     |
| `BF_PROXY_USE_INTERNAL_CA`             | 0 or 1                | If 1, Caddy's internal CA issues (untrusted) certificates instead of Let's Encrypt - for testing / local use.  | 0                     |
| `BF_PROXY_AUTO_PRIMARY`                | Domain name           | If set (with `BF_PROXY_AUTO_UPSTREAM`) and `conf.json` does not exist, it will be generated on startup.        | *None*                |
| `BF_PROXY_AUTO_UPSTREAM`               | URL                   | See `BF_PROXY_AUTO_PRIMARY`.                                                                                   | *None*                |
| `BF_PROXY_AUTO_ALIASES`                | Space-separated names | Aliases to add to the auto-generated `conf.json` (aliases will be redirected to the primary domain).           | *None*                |
| `BF_PROXY_AUTO_CUSTOM`                 | 0 or 1                | Mark the auto-generated domain as `custom`.                                                                    | 0                     |
| `BF_PROXY_MAINTENANCE_REFRESH_SECONDS` | Integer               | The number of seconds before the maintenance page auto-refreshes.                                              | 6                     |

## Configuration

Domains are defined in `/ssl/conf.json` - see `proxy-conf-sample.json` for an example and `proxy-conf-schema.json` for the full definition.  Add the `$schema` property to get validation and autocomplete in your editor.

```json
{
    "$schema": "https://raw.githubusercontent.com/bfren/docker-caddy-proxy/main/proxy-conf-schema.json",
    "domains": [
        {
            "primary": "example.com",
            "aliases": [ "www.example.com", "ex.com" ],
            "upstream": "http://example:5000",
            "redirectToPrimary": true
        }
    ]
}
```

| Property            | Description                                                                                                                                       |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `primary`           | **Required.**  The primary domain name.                                                                                                           |
| `aliases`           | Additional host names served by this domain.  Wildcards (e.g. `*.example.com`) require the DNS challenge.                                         |
| `upstream`          | **Required** (unless `custom`).  URL of the upstream server, e.g. `http://app:5000` - `https` is supported.  Use a list to load balance.          |
| `lb`                | Load balancing policy for multiple upstreams: `random` (default), `round_robin`, `least_conn`, `first`, `ip_hash`, `uri_hash`, `client_ip_hash`. |
| `challenge`         | `http` or `dns` - defaults to `BF_PROXY_ACME_CHALLENGE`.                                                                                          |
| `redirectToPrimary` | Redirect aliases to the primary domain - defaults to `BF_PROXY_SSL_REDIRECT_TO_CANONICAL`.                                                        |
| `auth`              | Enable HTTP basic auth: `true` for all users, or a list of user names - see `proxy-adduser`.                                                      |
| `headers`           | Response headers to add or override, e.g. `{ "X-Frame-Options": "DENY" }`.                                                                        |
| `routes`            | Additional routes, evaluated in order before the default upstream - see below.                                                                   |
| `custom`            | See [Custom Domain Configuration](#custom-domain-configuration).                                                                                  |

Existing `conf.json` files from nginx-proxy (using `primary`, `upstream`, `aliases` and `custom`) work without changes.

### Routes

Each route can have a `path` matcher (e.g. `/api/*` - if omitted the route matches everything) and must have exactly one of:

| Action     | Description                                                                                                                   |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `upstream` | Proxy to this upstream (or list of upstreams, with optional `lb`).  Add `stripPrefix` to remove a path prefix before proxying. |
| `redirect` | Redirect to this URL (default status 301, set `status` to change).  Caddy placeholders such as `{http.request.uri.path}` work.  |
| `root`     | Serve static files from this directory (mount it into the container).                                                         |

```json
"routes": [
    { "path": "/api/*", "upstream": [ "http://api1:8080", "http://api2:8080" ], "lb": "round_robin", "stripPrefix": "/api" },
    { "path": "/old/*", "redirect": "https://example.com/new{http.request.uri.path}" },
    { "path": "/files/*", "root": "/www/files" }
]
```

### Defaults

For every domain:

* HTTP requests are redirected to HTTPS, and certificates are requested and renewed automatically.
* Secure headers are added (`Strict-Transport-Security`, `X-Frame-Options`, `X-Content-Type-Options`, `X-XSS-Protection`).
* `X-Real-IP` is sent to the upstream, as well as Caddy's standard `X-Forwarded-*` headers.  WebSockets work automatically.
* If the upstream cannot be reached, or returns 502, 503 or 504, an auto-refreshing maintenance page is shown.
* Requests for unknown hosts are redirected to `BF_PROXY_DOMAIN`.


### AI Crawlers

When `BF_PROXY_BLOCK_AI_BOTS=1` (the default), requests from crawlers that collect AI training data receive 403 Forbidden.  The list comes from [ai.robots.txt](https://github.com/ai-robots-txt/ai.robots.txt): its `robots.json` is downloaded when the image is built (the release is set by the `AI_ROBOTS_VERSION` build argument), and only crawlers whose `function` is training data collection are kept - AI search crawlers, assistants and user-triggered agents (e.g. `OAI-SearchBot`, `ChatGPT-User`, `PerplexityBot`) are not blocked.  The list is saved to `/usr/share/caddy-proxy/ai-bots.txt`.

## Custom Domain Configuration

Each domain's complete Caddy configuration is stored in `/sites/<primary>.json`:

* `route` - the domain's route (added to the HTTPS server)
* `errors` - the domain's error route (shows the maintenance page)
* `tls` - the domain's certificate automation policy, including the ACME challenge

If the file does not exist it is generated from the standard base.  What happens next depends on `custom`:

* `"custom": false` (default) - the file is regenerated every time the container starts (or `proxy-regenerate` is run), so any changes you make to it will be lost.  To add to the generated configuration, add `*.json` files to `/sites/<primary>.d` - each should contain a Caddy [route](https://caddyserver.com/docs/json/apps/http/servers/routes/) object or an array of routes, which are added (in file name order) before the generated routes.
* `"custom": true` - if the file already exists it is left alone, giving you complete control of the domain's configuration, starting from the standard base.  Run `proxy-regenerate -d <primary> -f` to regenerate it.

## DNS Challenge

The DNS challenge allows certificates to be issued for wildcard domains, and for servers that are not reachable on port 80.  Caddy is built with the [deSEC](https://github.com/caddy-dns/desec) DNS provider module.

1. Create a token in your deSEC account with permission to manage the relevant domains.
2. Set `BF_PROXY_DESEC_TOKEN` to the token, and either set `BF_PROXY_ACME_CHALLENGE=dns` or `"challenge": "dns"` for each domain.
3. If certificate requests fail because the record has not propagated, set `BF_PROXY_DNS_PROPAGATION_DELAY` (e.g. `60s`) and / or `BF_PROXY_DNS_RESOLVERS` (e.g. `1.1.1.1`).

The token is not written to the generated configuration files - Caddy reads it from the environment at runtime.

## Helper Functions

| Function           | Arguments                  | Description                                                                                                     |
| ------------------ | -------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `proxy-regenerate` | -d: only domain, -f: force | Regenerates configuration from `conf.json` and reloads Caddy (with force, custom domain files are regenerated). |
| `proxy-reload`     | *None*                     | Validates the current configuration and reloads Caddy.                                                          |
| `proxy-validate`   | *None*                     | Validates `conf.json` and the current Caddy configuration.                                                      |
| `proxy-cleanup`    | -l: live mode              | Removes configuration and certificates for domains not defined in `conf.json` (dry run unless `-l` is set).     |
| `proxy-adduser`    | 0: username, 1: password   | Adds (or updates) a user for HTTP basic auth, then regenerates configuration.                                   |
| `proxy-deluser`    | 0: username                | Removes a user, then regenerates configuration.                                                                 |

## Migrating from nginx-proxy

1. Copy `/ssl/conf.json` to the new `/ssl` volume - it is converted automatically on startup.  The original is kept as `/ssl/conf.json.nginx-proxy` and `$schema` is updated.  Anything that cannot be converted (e.g. custom Nginx configuration) is reported in the container log.
2. In your docker compose file, change the image to `bfren/caddy-proxy` and rename environment variables from `PROXY_*` to `BF_PROXY_*` - old variable names are ignored.  The following are no longer used: `PROXY_ENABLE_AUTO_UPDATE` (Caddy renews automatically), `PROXY_ENABLE_NAXSI` (NAXSI has been removed), `PROXY_SSL_KEY_BITS`, `PROXY_SSL_DHPARAM_BITS`, `PROXY_GETSSL_SKIP_HTTP_TOKEN_CHECK` and `PROXY_UPSTREAM_DNS_RESOLVER` (upstreams are resolved when requests are made).
3. Custom Nginx configuration in `/sites` cannot be converted automatically - the new per-domain files are Caddy JSON.
4. Existing certificates are not reused - Caddy will request new ones.  Caddy requests one certificate per host name (getssl used one certificate per primary domain), so check [Let's Encrypt rate limits](https://letsencrypt.org/docs/rate-limits/) if you have many domains, and leave `BF_PROXY_LETS_ENCRYPT_LIVE=0` until everything works.
5. `nginx-adduser` is replaced by `proxy-adduser` - users are stored in `/ssl/users.json` and enabled per domain using `auth`.

## Licence

> [MIT](https://mit.bfren.dev/2020)

## Copyright

> Copyright (c) 2020-2026 [bfren](https://bfren.dev) (unless otherwise stated)
